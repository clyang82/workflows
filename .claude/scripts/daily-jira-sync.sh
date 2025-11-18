#!/usr/bin/env bash

# Daily Jira Sync - Sync Jira issues to TODO list and Slack
# Usage: ./daily-jira-sync.sh [--slack] [--save]

set -e

# Ensure bash 4+ for associative arrays
if ((BASH_VERSINFO[0] < 4)); then
    echo "This script requires bash 4 or higher"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
# SLACK_WEBHOOK_URL is read from environment variable
SEND_TO_SLACK=true
OUTPUT_DIR="${HOME}/Documents/daily-jira-sync"
TODAY=$(date +%Y-%m-%d)
WEEKLY_DIR="${OUTPUT_DIR}/weekly"
QUARTERLY_DIR="${OUTPUT_DIR}/quarterly"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0"
            echo ""
            echo "Daily Jira Sync - Automatically syncs your Jira issues to TODO list"
            echo ""
            echo "Features:"
            echo "  • Fetches assigned Jira issues (In Progress, Review, New, Open)"
            echo "  • Displays formatted TODO list with priorities"
            echo "  • Sends to Slack (if SLACK_WEBHOOK_URL is set)"
            echo "  • Generates weekly reports on Mondays (queries Jira for last week)"
            echo ""
            echo "Environment Variables:"
            echo "  SLACK_WEBHOOK_URL    Slack webhook URL for notifications"
            echo ""
            echo "Output Locations:"
            echo "  Weekly:   ~/Documents/daily-jira-sync/weekly/week-NN-YYYY.md"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create output directories
mkdir -p "$OUTPUT_DIR" "$WEEKLY_DIR" "$QUARTERLY_DIR"

# Function to format issue priority
format_priority() {
    local priority=$1
    case $priority in
        Critical|Blocker)
            echo "🔴"
            ;;
        Major)
            echo "🟡"
            ;;
        Minor)
            echo "🟢"
            ;;
        *)
            echo "⚪"
            ;;
    esac
}

# Function to format issue status
format_status() {
    local status=$1
    case $status in
        "In Progress")
            echo "🔄"
            ;;
        New|Open)
            echo "🆕"
            ;;
        Review)
            echo "👀"
            ;;
        Closed|Done)
            echo "✅"
            ;;
        *)
            echo "📋"
            ;;
    esac
}

# Function to escape JSON strings
escape_json() {
    local string="$1"
    # Escape backslashes, quotes, and newlines
    echo "$string" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n'
}

echo -e "${BLUE}📊 Fetching Jira issues for ${TODAY}...${NC}\n"

# Query Jira for assigned issues
# Using jira CLI to get issues assigned to me (excluding Closed/Done)
JIRA_OUTPUT=$(jira issue list --assignee $(jira me) --plain --columns key,summary,status,priority 2>/dev/null | grep -v -E "Closed|Done|Resolved" || echo "")

if [ -z "$JIRA_OUTPUT" ]; then
    echo -e "${YELLOW}⚠️  No Jira issues found or jira CLI not configured${NC}"
    exit 0
fi

# Parse and format issues
TODO_LIST=""
SLACK_CRITICAL=""
SLACK_MAJOR=""
SLACK_INPROGRESS=""
SLACK_OTHER=""
ISSUE_COUNT=0
HIGH_PRIORITY_COUNT=0

# Header
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}       📋 Daily Jira TODO List - ${TODAY}${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}\n"

# Parse each line (skip header)
while IFS=$'\t' read -r KEY SUMMARY STATUS PRIORITY; do
    # Skip header line
    if [[ "$KEY" == "KEY" ]] || [[ -z "$KEY" ]]; then
        continue
    fi

    ISSUE_COUNT=$((ISSUE_COUNT + 1))

    # Count high priority items
    if [[ "$PRIORITY" == "Critical" ]] || [[ "$PRIORITY" == "Blocker" ]]; then
        HIGH_PRIORITY_COUNT=$((HIGH_PRIORITY_COUNT + 1))
    fi

    PRIORITY_ICON=$(format_priority "$PRIORITY")
    STATUS_ICON=$(format_status "$STATUS")

    # Console output
    echo -e "${PRIORITY_ICON} ${STATUS_ICON} ${GREEN}${KEY}${NC} - ${SUMMARY}"
    echo -e "   Status: ${YELLOW}${STATUS}${NC} | Priority: ${YELLOW}${PRIORITY}${NC}"
    echo -e "   🔗 https://issues.redhat.com/browse/${KEY}\n"

    # Build Slack message - group by priority and status
    SLACK_LINE=$'• <https://issues.redhat.com/browse/'"${KEY}"$'|*'"${KEY}"$'*> '"${SUMMARY}"$'\n'

    if [[ "$PRIORITY" == "Critical" ]] || [[ "$PRIORITY" == "Blocker" ]]; then
        SLACK_CRITICAL+="$SLACK_LINE"
    elif [[ "$STATUS" == "In Progress" ]]; then
        SLACK_INPROGRESS+="$SLACK_LINE"
    elif [[ "$PRIORITY" == "Major" ]]; then
        SLACK_MAJOR+="$SLACK_LINE"
    else
        SLACK_OTHER+="$SLACK_LINE"
    fi

done <<< "$JIRA_OUTPUT"

# Summary
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Total Issues: ${ISSUE_COUNT}${NC}"
if [ $HIGH_PRIORITY_COUNT -gt 0 ]; then
    echo -e "${RED}🔥 High Priority: ${HIGH_PRIORITY_COUNT}${NC}"
fi
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}\n"

# Send to Slack if requested and configured
if [ "$SEND_TO_SLACK" = true ]; then
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        echo -e "${RED}❌ Slack webhook URL not configured${NC}"
        echo -e "${YELLOW}💡 Set SLACK_WEBHOOK_URL environment variable${NC}"
        echo -e "${YELLOW}   Example:${NC}"
        echo -e "${YELLOW}   export SLACK_WEBHOOK_URL=\"https://hooks.slack.com/services/YOUR/WEBHOOK/URL\"${NC}\n"
    else
        # Build formatted message with groups
        SLACK_MESSAGE=""

        if [ -n "$SLACK_CRITICAL" ]; then
            SLACK_MESSAGE+=$'*🔴 Critical Priority*\n'"${SLACK_CRITICAL}"$'\n'
        fi

        if [ -n "$SLACK_INPROGRESS" ]; then
            SLACK_MESSAGE+=$'*🔄 In Progress*\n'"${SLACK_INPROGRESS}"$'\n'
        fi

        if [ -n "$SLACK_MAJOR" ]; then
            SLACK_MESSAGE+=$'*🟡 Major Priority*\n'"${SLACK_MAJOR}"$'\n'
        fi

        if [ -n "$SLACK_OTHER" ]; then
            SLACK_MESSAGE+=$'*📋 Other Issues*\n'"${SLACK_OTHER}"
        fi

        # Truncate message if too long (Slack has 3000 char limit per block)
        if [ ${#SLACK_MESSAGE} -gt 2800 ]; then
            SLACK_MESSAGE="${SLACK_MESSAGE:0:2800}"$'...\n\n_Message truncated. View full list in saved file._'
        fi

        # Use jq to properly escape JSON
        SLACK_PAYLOAD=$(jq -n \
            --arg today "$TODAY" \
            --arg count "$ISSUE_COUNT" \
            --arg high "$HIGH_PRIORITY_COUNT" \
            --arg message "$SLACK_MESSAGE" \
            '{
                blocks: [
                    {
                        type: "header",
                        text: {
                            type: "plain_text",
                            text: ("📋 Daily Jira TODO List - " + $today)
                        }
                    },
                    {
                        type: "section",
                        text: {
                            type: "mrkdwn",
                            text: ("*Total Issues:* " + $count + " | *High Priority:* " + $high)
                        }
                    },
                    {
                        type: "divider"
                    },
                    {
                        type: "section",
                        text: {
                            type: "mrkdwn",
                            text: $message
                        }
                    }
                ]
            }')

        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
            --data "$SLACK_PAYLOAD" \
            "$SLACK_WEBHOOK_URL")

        if [ "$HTTP_STATUS" = "200" ]; then
            echo -e "${GREEN}✓ Sent to Slack successfully${NC}"
        else
            echo -e "${RED}❌ Failed to send to Slack (HTTP ${HTTP_STATUS})${NC}"
        fi
    fi
fi

echo ""
if [ -z "$SLACK_WEBHOOK_URL" ]; then
    echo -e "${BLUE}💡 Tip: Set SLACK_WEBHOOK_URL environment variable to enable Slack notifications${NC}"
fi

# Generate weekly report on Mondays
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday
if [ "$DAY_OF_WEEK" = "1" ]; then
    echo -e "\n${BLUE}📊 It's Monday! Generating last week's report...${NC}\n"

    # Calculate last week's dates (Monday to Sunday)
    # Today is Monday, so last week is: last Monday (7 days ago) to yesterday (Sunday)
    LAST_MONDAY=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)
    LAST_SUNDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d 2>/dev/null)
    WEEK_NUM=$(date -j -f "%Y-%m-%d" "$LAST_MONDAY" +%V 2>/dev/null || date -d "$LAST_MONDAY" +%V 2>/dev/null)
    WEEK_YEAR=$(date -j -f "%Y-%m-%d" "$LAST_MONDAY" +%Y 2>/dev/null || date -d "$LAST_MONDAY" +%Y 2>/dev/null)

    echo -e "${YELLOW}Querying Jira for issues updated from ${LAST_MONDAY} to ${LAST_SUNDAY}...${NC}"

    # Query Jira using JQL for issues updated during last week
    WEEKLY_JIRA_OUTPUT=$(jira issue list \
        --jql "assignee = currentUser() AND updated >= '${LAST_MONDAY}' AND updated <= '${LAST_SUNDAY}'" \
        --plain \
        --columns key,summary,status,priority \
        2>/dev/null || echo "")

    # Initialize counters
    declare -A UNIQUE_ISSUES
    declare -A ISSUE_STATUS
    declare -A ISSUE_SUMMARY
    declare -A ISSUE_PRIORITY
    declare -A STATUS_COUNTS
    declare -A PRIORITY_COUNTS

    # Parse Jira output
    while IFS=$'\t' read -r KEY SUMMARY STATUS PRIORITY; do
        if [[ -z "$KEY" ]] || [[ "$KEY" == "KEY" ]]; then
            continue
        fi

        UNIQUE_ISSUES["$KEY"]=1
        ISSUE_SUMMARY["$KEY"]="$SUMMARY"
        ISSUE_STATUS["$KEY"]="$STATUS"
        ISSUE_PRIORITY["$KEY"]="$PRIORITY"

        STATUS_COUNTS["$STATUS"]=$((${STATUS_COUNTS["$STATUS"]:-0} + 1))
        PRIORITY_COUNTS["$PRIORITY"]=$((${PRIORITY_COUNTS["$PRIORITY"]:-0} + 1))
    done <<< "$WEEKLY_JIRA_OUTPUT"

    # Generate weekly report
    WEEKLY_REPORT="${WEEKLY_DIR}/week-${WEEK_NUM}-${WEEK_YEAR}.md"

    cat > "$WEEKLY_REPORT" <<WEEKLY_EOF
# Weekly Jira Report - Week ${WEEK_NUM} (${WEEK_YEAR})

**Period:** ${LAST_MONDAY} to ${LAST_SUNDAY}
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Total Issues Updated:** ${#UNIQUE_ISSUES[@]}

---

## Summary Statistics

### By Status
WEEKLY_EOF

    # Add status counts
    for status in "${!STATUS_COUNTS[@]}"; do
        echo "- **${status}:** ${STATUS_COUNTS[$status]}" >> "$WEEKLY_REPORT"
    done

    cat >> "$WEEKLY_REPORT" <<WEEKLY_EOF

### By Priority
WEEKLY_EOF

    # Add priority counts
    for priority in "${!PRIORITY_COUNTS[@]}"; do
        echo "- **${priority}:** ${PRIORITY_COUNTS[$priority]}" >> "$WEEKLY_REPORT"
    done

    cat >> "$WEEKLY_REPORT" <<WEEKLY_EOF

---

## Issues by Status

WEEKLY_EOF

    # List issues grouped by status
    for status in "In Progress" "Review" "New" "Open"; do
        has_issues=false
        for issue in $(echo "${!UNIQUE_ISSUES[@]}" | tr ' ' '\n' | sort); do
            if [ "${ISSUE_STATUS[$issue]}" == "$status" ]; then
                if ! $has_issues; then
                    echo -e "\n### ${status}\n" >> "$WEEKLY_REPORT"
                    has_issues=true
                fi
                priority="${ISSUE_PRIORITY[$issue]}"
                priority_icon=$(format_priority "$priority")
                echo "- ${priority_icon} **${issue}**: ${ISSUE_SUMMARY[$issue]}" >> "$WEEKLY_REPORT"
            fi
        done
    done

    # Add other statuses
    for issue in $(echo "${!UNIQUE_ISSUES[@]}" | tr ' ' '\n' | sort); do
        status="${ISSUE_STATUS[$issue]}"
        if [[ ! "$status" =~ ^(In\ Progress|Review|New|Open)$ ]]; then
            if [ -z "$other_header" ]; then
                echo -e "\n### Other\n" >> "$WEEKLY_REPORT"
                other_header=1
            fi
            priority="${ISSUE_PRIORITY[$issue]}"
            priority_icon=$(format_priority "$priority")
            echo "- ${priority_icon} **${issue}**: ${ISSUE_SUMMARY[$issue]} [${status}]" >> "$WEEKLY_REPORT"
        fi
    done

    echo -e "${GREEN}✓ Weekly report generated: ${WEEKLY_REPORT}${NC}"
    echo -e "${BLUE}📊 Week ${WEEK_NUM}: ${#UNIQUE_ISSUES[@]} issues updated last week${NC}"
    echo -e "${BLUE}   Period: ${LAST_MONDAY} to ${LAST_SUNDAY}${NC}\n"
fi
