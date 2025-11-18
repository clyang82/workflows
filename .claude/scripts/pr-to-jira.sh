#!/bin/bash

# PR to Jira - Automatically create Jira issue from GitHub PR
# Estimates effort based on PR complexity
# Usage: ./pr-to-jira.sh <PR-NUMBER> [--project PROJECT] [--auto]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Default configuration
DEFAULT_PROJECT="ACM"
DEFAULT_COMPONENT="Global Hub"
DEFAULT_TYPE="Bug"
DEFAULT_LABEL="GlobalHub"
DEFAULT_VERSION="Global Hub 1.7.0"
DEFAULT_ACTIVITY_TYPE_BUG="Quality / Stability / Reliability"
DEFAULT_ACTIVITY_TYPE_OTHER="Product / Portfolio Work"
DEFAULT_SEVERITY="Important"
DEFAULT_STORY_POINTS="0.5"
AUTO_MODE=false
QE_APPLICABLE=false
PR_NUMBER=""
PROJECT="$DEFAULT_PROJECT"
ISSUE_TYPE="$DEFAULT_TYPE"
SEVERITY="$DEFAULT_SEVERITY"
STORY_POINTS="$DEFAULT_STORY_POINTS"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --type)
            ISSUE_TYPE="$2"
            shift 2
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --story-points)
            STORY_POINTS="$2"
            shift 2
            ;;
        --qe-applicable)
            QE_APPLICABLE=true
            shift
            ;;
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 <PR-NUMBER> [OPTIONS]"
            echo ""
            echo "Create a Jira issue from a GitHub PR with automatic effort estimation"
            echo ""
            echo "Arguments:"
            echo "  PR-NUMBER       The GitHub PR number to process"
            echo ""
            echo "Options:"
            echo "  --project NAME        Jira project (default: ${DEFAULT_PROJECT})"
            echo "  --type TYPE           Issue type: Bug, Task, Story (default: ${DEFAULT_TYPE})"
            echo "  --severity LEVEL      Bug severity: Critical, Important, Normal, Low (default: ${DEFAULT_SEVERITY})"
            echo "  --story-points NUM    Story points (default: ${DEFAULT_STORY_POINTS})"
            echo "  --qe-applicable       Skip adding 'QE-NotApplicable' label (for bugs that need QE)"
            echo "  --auto                Skip confirmation prompts"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 123"
            echo "  $0 123 --type Bug"
            echo "  $0 123 --type Bug --severity Critical --story-points 1"
            echo "  $0 123 --type Bug --qe-applicable"
            echo "  $0 123 --project MGMT --type Bug --severity Important"
            echo "  $0 123 --type Bug --auto"
            echo ""
            echo "Environment Variables:"
            echo "  GH_TOKEN        GitHub token for API access (optional if gh CLI configured)"
            exit 0
            ;;
        *)
            if [[ -z "$PR_NUMBER" ]]; then
                PR_NUMBER="$1"
            else
                echo "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate PR number
if [[ -z "$PR_NUMBER" ]]; then
    echo -e "${RED}❌ Error: PR number is required${NC}"
    echo "Usage: $0 <PR-NUMBER>"
    exit 1
fi

echo -e "${BLUE}🔍 Fetching PR #${PR_NUMBER} information...${NC}\n"

# Fetch PR details using gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it with: brew install gh"
    exit 1
fi

# Get PR details
PR_DATA=$(gh pr view "$PR_NUMBER" --json title,body,author,url,additions,deletions,changedFiles,labels,state)

PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_BODY=$(echo "$PR_DATA" | jq -r '.body // ""')
PR_AUTHOR=$(echo "$PR_DATA" | jq -r '.author.login')
PR_URL=$(echo "$PR_DATA" | jq -r '.url')
PR_ADDITIONS=$(echo "$PR_DATA" | jq -r '.additions')
PR_DELETIONS=$(echo "$PR_DATA" | jq -r '.deletions')
PR_FILES=$(echo "$PR_DATA" | jq -r '.changedFiles')
PR_STATE=$(echo "$PR_DATA" | jq -r '.state')

TOTAL_CHANGES=$((PR_ADDITIONS + PR_DELETIONS))

# Display PR information
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${PURPLE}          PR #${PR_NUMBER} Details${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Title:${NC} ${PR_TITLE}"
echo -e "${GREEN}Author:${NC} ${PR_AUTHOR}"
echo -e "${GREEN}URL:${NC} ${PR_URL}"
echo -e "${GREEN}State:${NC} ${PR_STATE}"
echo -e "${GREEN}Changes:${NC} +${PR_ADDITIONS} -${PR_DELETIONS} (~${TOTAL_CHANGES} lines)"
echo -e "${GREEN}Files:${NC} ${PR_FILES}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}\n"

# Estimate effort based on complexity
# Small: < 50 lines, 1-3 files
# Medium: 50-200 lines, 4-10 files
# Large: 200-500 lines, 11-20 files
# Extra Large: > 500 lines or > 20 files

EFFORT_HOURS=0
EFFORT_LABEL=""
COMPLEXITY=""

if [ $TOTAL_CHANGES -lt 50 ] && [ $PR_FILES -le 3 ]; then
    EFFORT_HOURS=1
    EFFORT_LABEL="1h"
    COMPLEXITY="Small"
elif [ $TOTAL_CHANGES -lt 200 ] && [ $PR_FILES -le 10 ]; then
    EFFORT_HOURS=4
    EFFORT_LABEL="4h"
    COMPLEXITY="Medium"
elif [ $TOTAL_CHANGES -lt 500 ] && [ $PR_FILES -le 20 ]; then
    EFFORT_HOURS=8
    EFFORT_LABEL="1d"
    COMPLEXITY="Large"
else
    EFFORT_HOURS=16
    EFFORT_LABEL="2d"
    COMPLEXITY="Extra Large"
fi

echo -e "${BLUE}📊 Effort Estimation:${NC}"
echo -e "   Complexity: ${YELLOW}${COMPLEXITY}${NC}"
echo -e "   Estimated Effort: ${YELLOW}${EFFORT_LABEL} (${EFFORT_HOURS}h)${NC}"
echo -e "   Calculation: ${PR_FILES} files, ${TOTAL_CHANGES} lines changed\n"

# Prepare Jira issue summary and description
# Clean up PR title: remove emojis, PR prefixes like [release-x.y], etc.
CLEAN_TITLE=$(echo "$PR_TITLE" | sed -E 's/\[release-[0-9.]+\] //g' | sed -E 's/:[a-z_]+: //g' | sed -E 's/^(✨|🐛|📖|📝|⚠️|🌱|❓) //g')
JIRA_SUMMARY="${CLEAN_TITLE}"

# Parse PR body to extract summary if it contains "## Summary"
PR_SUMMARY=$(echo "$PR_BODY" | awk '/## Summary/,/##/ {if (!/## Summary/ && !/^##/) print}' | sed '/^$/d' | head -5)

# Build Jira description using wiki markup
JIRA_DESCRIPTION="h2. Problem

${PR_SUMMARY:-This PR addresses issues found in the codebase.}

h2. Changes

* Modified files: ${PR_FILES}
* Lines changed: +${PR_ADDITIONS} -${PR_DELETIONS}

h2. Related PR

* [PR #${PR_NUMBER}|${PR_URL}]

h2. Effort Estimation

* Complexity: ${COMPLEXITY}
* Estimated Time: ${EFFORT_LABEL} (${EFFORT_HOURS} hours)

---
_Auto-generated from PR #${PR_NUMBER}_"

# Get current GH Train sprint for preview
PREVIEW_SPRINT=$(jira sprint list --plain 2>/dev/null | grep -i "GH Train" | grep "active" | head -1)
PREVIEW_SPRINT_NAME=$(echo "$PREVIEW_SPRINT" | awk '{print $2}')
PREVIEW_SPRINT_ID=$(echo "$PREVIEW_SPRINT" | awk '{print $1}')

echo -e "${YELLOW}📝 Jira Issue Preview:${NC}"
echo -e "   Project: ${PROJECT}"
echo -e "   Component: ${DEFAULT_COMPONENT}"
echo -e "   Summary: ${JIRA_SUMMARY}"
echo -e "   Type: ${ISSUE_TYPE}"
if [ "$ISSUE_TYPE" = "Bug" ]; then
    echo -e "   Activity Type: ${DEFAULT_ACTIVITY_TYPE_BUG}"
else
    echo -e "   Activity Type: ${DEFAULT_ACTIVITY_TYPE_OTHER}"
fi
echo -e "   Severity: ${SEVERITY}"
if [ "$ISSUE_TYPE" = "Bug" ] && [ "$QE_APPLICABLE" = false ]; then
    echo -e "   Labels: ${DEFAULT_LABEL}, QE-NotApplicable"
else
    echo -e "   Label: ${DEFAULT_LABEL}"
fi
echo -e "   Affects Version: ${DEFAULT_VERSION}"
echo -e "   Fix Version: ${DEFAULT_VERSION}"
echo -e "   Git Pull Request: ${PR_URL}"
echo -e "   Story Points: ${STORY_POINTS}"
if [ -n "$PREVIEW_SPRINT_NAME" ]; then
    echo -e "   Sprint: ${PREVIEW_SPRINT_NAME}"
fi
echo -e "   Time Estimate: ${EFFORT_LABEL}\n"

# Confirmation
if [ "$AUTO_MODE" = false ]; then
    read -p "Create Jira issue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Check if jira CLI is available
if ! command -v jira &> /dev/null; then
    echo -e "${RED}❌ Error: Jira CLI is not installed${NC}"
    echo "Install it with: brew install jira-cli"
    exit 1
fi

echo -e "${BLUE}🚀 Creating Jira issue...${NC}\n"

# Get current GH Train sprint
CURRENT_SPRINT=$(jira sprint list --plain 2>/dev/null | grep -i "GH Train" | grep "active" | head -1 | awk '{print $1}')

# Create Jira issue
# Note: Adjust the command based on your Jira configuration
if [ "$ISSUE_TYPE" = "Bug" ]; then
    # For bugs, use "Quality / Stability / Reliability"
    # Add QE-NotApplicable label by default unless --qe-applicable flag is set
    if [ "$QE_APPLICABLE" = true ]; then
        JIRA_KEY=$(jira issue create \
            --project "$PROJECT" \
            --type "$ISSUE_TYPE" \
            --summary "$JIRA_SUMMARY" \
            --body "$JIRA_DESCRIPTION" \
            --component "$DEFAULT_COMPONENT" \
            --label "$DEFAULT_LABEL" \
            --affects-version "$DEFAULT_VERSION" \
            --fix-version "$DEFAULT_VERSION" \
            --custom activity-type="${DEFAULT_ACTIVITY_TYPE_BUG}" \
            --custom severity="${SEVERITY}" \
            --custom git-pull-request="${PR_URL}" \
            --custom story-points="${STORY_POINTS}" \
            --priority Normal \
            --assignee $(jira me) \
            --no-input 2>&1 | grep -oE "${PROJECT}-[0-9]+" | head -1)
    else
        JIRA_KEY=$(jira issue create \
            --project "$PROJECT" \
            --type "$ISSUE_TYPE" \
            --summary "$JIRA_SUMMARY" \
            --body "$JIRA_DESCRIPTION" \
            --component "$DEFAULT_COMPONENT" \
            --label "$DEFAULT_LABEL" \
            --label "QE-NotApplicable" \
            --affects-version "$DEFAULT_VERSION" \
            --fix-version "$DEFAULT_VERSION" \
            --custom activity-type="${DEFAULT_ACTIVITY_TYPE_BUG}" \
            --custom severity="${SEVERITY}" \
            --custom git-pull-request="${PR_URL}" \
            --custom story-points="${STORY_POINTS}" \
            --priority Normal \
            --assignee $(jira me) \
            --no-input 2>&1 | grep -oE "${PROJECT}-[0-9]+" | head -1)
    fi
else
    # For tasks and other types, use "Product / Portfolio Work"
    JIRA_KEY=$(jira issue create \
        --project "$PROJECT" \
        --type "$ISSUE_TYPE" \
        --summary "$JIRA_SUMMARY" \
        --body "$JIRA_DESCRIPTION" \
        --component "$DEFAULT_COMPONENT" \
        --label "$DEFAULT_LABEL" \
        --affects-version "$DEFAULT_VERSION" \
        --fix-version "$DEFAULT_VERSION" \
        --custom activity-type="${DEFAULT_ACTIVITY_TYPE_OTHER}" \
        --custom severity="${SEVERITY}" \
        --custom git-pull-request="${PR_URL}" \
        --custom story-points="${STORY_POINTS}" \
        --priority Normal \
        --assignee $(jira me) \
        --no-input 2>&1 | grep -oE "${PROJECT}-[0-9]+" | head -1)
fi

if [ -z "$JIRA_KEY" ]; then
    echo -e "${RED}❌ Failed to create Jira issue${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Jira issue created: ${JIRA_KEY}${NC}"
echo -e "${BLUE}🔗 ${GREEN}https://issues.redhat.com/browse/${JIRA_KEY}${NC}\n"

# Move issue to "In Progress" state
echo -e "${BLUE}🔄 Moving issue to In Progress...${NC}"
jira issue move "$JIRA_KEY" "In Progress" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Issue moved to In Progress${NC}\n"
else
    echo -e "${YELLOW}⚠️  Could not move to In Progress (may need to be done manually)${NC}\n"
fi

# Add to current GH Train sprint if found
if [ -n "$CURRENT_SPRINT" ]; then
    echo -e "${BLUE}📅 Adding to sprint GH Train (ID: ${CURRENT_SPRINT})...${NC}"
    jira sprint add "$CURRENT_SPRINT" "$JIRA_KEY" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Added to current GH Train sprint${NC}\n"
    else
        echo -e "${YELLOW}⚠️  Could not add to sprint (may need to be done manually)${NC}\n"
    fi
fi

# Update PR description with Jira link
echo -e "${BLUE}💬 Updating PR description...${NC}"

# Get current PR body and append Jira info if not already present
CURRENT_BODY=$(gh pr view "$PR_NUMBER" --json body -q '.body')

# Check if Jira link already exists in the body
if [[ "$CURRENT_BODY" =~ "Jira:" ]] || [[ "$CURRENT_BODY" =~ "issues.redhat.com/browse/" ]]; then
    # Update existing Jira link
    UPDATED_BODY=$(echo "$CURRENT_BODY" | sed -E "s|Jira: \[ACM-[0-9]+\]\(https://issues.redhat.com/browse/ACM-[0-9]+\)|Jira: [${JIRA_KEY}](https://issues.redhat.com/browse/${JIRA_KEY})|")
else
    # Append Jira info to the end
    JIRA_INFO="

---

**Jira:** [${JIRA_KEY}](https://issues.redhat.com/browse/${JIRA_KEY})
**Complexity:** ${COMPLEXITY}
**Estimated Time:** ${EFFORT_LABEL}"
    UPDATED_BODY="${CURRENT_BODY}${JIRA_INFO}"
fi

# Update PR description
echo "$UPDATED_BODY" | gh pr edit "$PR_NUMBER" --body-file -

echo -e "${GREEN}✓ PR description updated${NC}\n"

# Log to file
LOG_DIR="${HOME}/Documents/daily-jira-sync/pr-tracking"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/pr-to-jira.log"

cat >> "$LOG_FILE" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') | PR #${PR_NUMBER} | ${JIRA_KEY} | ${EFFORT_LABEL} | ${COMPLEXITY}
EOF

echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Success!${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "   PR: ${PR_URL}"
echo -e "   Jira: https://issues.redhat.com/browse/${JIRA_KEY}"
echo -e "   Effort: ${EFFORT_LABEL} (${EFFORT_HOURS}h)"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}\n"
