#!/usr/bin/env bash

# Quarterly Report Generator
# Aggregates weekly Jira sync data into quarterly reports
# Usage: ./generate-quarterly-report.sh [YYYY-QN]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

SYNC_DIR="${HOME}/Documents/daily-jira-sync"
WEEKLY_DIR="${SYNC_DIR}/weekly"
QUARTERLY_DIR="${SYNC_DIR}/quarterly"

# Get quarter from argument or calculate current quarter
if [ -n "$1" ]; then
    QUARTER_YEAR=$(echo $1 | cut -d'-' -f1)
    QUARTER_NUM=$(echo $1 | cut -d'-' -f2 | tr -d 'Q')
else
    CURRENT_MONTH=$(date +%m)
    QUARTER_NUM=$(( (CURRENT_MONTH - 1) / 3 + 1 ))
    QUARTER_YEAR=$(date +%Y)
fi

QUARTER_NAME="${QUARTER_YEAR}-Q${QUARTER_NUM}"
OUTPUT_FILE="${QUARTERLY_DIR}/${QUARTER_NAME}.md"

# Calculate week range for quarter
case $QUARTER_NUM in
    1) MONTHS="01 02 03" ;;
    2) MONTHS="04 05 06" ;;
    3) MONTHS="07 08 09" ;;
    4) MONTHS="10 11 12" ;;
esac

echo -e "${BLUE}📊 Generating Quarterly Report for ${QUARTER_NAME}...${NC}\n"

# Create quarterly directory
mkdir -p "$QUARTERLY_DIR"

# Initialize counters
declare -A ISSUE_STATUS
declare -A ISSUE_PRIORITY
declare -A ISSUE_COUNT_BY_WEEK
TOTAL_ISSUES=0
UNIQUE_ISSUES=()

# Header
cat > "$OUTPUT_FILE" <<EOF
# Quarterly Report - ${QUARTER_NAME}

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Period:** Q${QUARTER_NUM} ${QUARTER_YEAR}

---

## Executive Summary

EOF

# Process all daily files for this quarter
for MONTH in $MONTHS; do
    for DAY in {01..31}; do
        DAILY_FILE="${SYNC_DIR}/jira-todos-${QUARTER_YEAR}-${MONTH}-${DAY}.md"

        if [ -f "$DAILY_FILE" ]; then
            echo -e "${YELLOW}Processing ${QUARTER_YEAR}-${MONTH}-${DAY}...${NC}"

            # Extract issue keys and count
            while IFS= read -r line; do
                if [[ $line =~ ^\-\ \[\ \]\ (ACM-[0-9]+): ]]; then
                    ISSUE_KEY="${BASH_REMATCH[1]}"

                    # Track unique issues
                    if [[ ! " ${UNIQUE_ISSUES[@]} " =~ " ${ISSUE_KEY} " ]]; then
                        UNIQUE_ISSUES+=("$ISSUE_KEY")
                    fi

                    # Extract status
                    if [[ $line =~ \[([^\]]+)\]$ ]]; then
                        STATUS="${BASH_REMATCH[1]}"
                        ISSUE_STATUS["$STATUS"]=$((${ISSUE_STATUS["$STATUS"]:-0} + 1))
                    fi

                    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
                fi
            done < "$DAILY_FILE"

            # Count issues by week
            WEEK_NUM=$(date -j -f "%Y-%m-%d" "${QUARTER_YEAR}-${MONTH}-${DAY}" "+%V" 2>/dev/null || echo "00")
            ISSUE_COUNT_BY_WEEK["$WEEK_NUM"]=$((${ISSUE_COUNT_BY_WEEK["$WEEK_NUM"]:-0} + 1))
        fi
    done
done

# Calculate statistics
UNIQUE_COUNT=${#UNIQUE_ISSUES[@]}
IN_PROGRESS=${ISSUE_STATUS["In Progress"]:-0}
NEW_ITEMS=${ISSUE_STATUS["New"]:-0}
REVIEW_ITEMS=${ISSUE_STATUS["Review"]:-0}

# Write summary
cat >> "$OUTPUT_FILE" <<EOF
### 📈 Key Metrics

| Metric | Value |
|--------|-------|
| **Total Issue Mentions** | ${TOTAL_ISSUES} |
| **Unique Issues** | ${UNIQUE_COUNT} |
| **In Progress** | ${IN_PROGRESS} |
| **In Review** | ${REVIEW_ITEMS} |
| **New/Open** | ${NEW_ITEMS} |

### 📊 Status Distribution

EOF

# Add status chart
for STATUS in "${!ISSUE_STATUS[@]}"; do
    COUNT=${ISSUE_STATUS[$STATUS]}
    PERCENTAGE=$(awk "BEGIN {printf \"%.1f\", ($COUNT / $TOTAL_ISSUES) * 100}")
    BAR_LENGTH=$(awk "BEGIN {printf \"%.0f\", ($COUNT / $TOTAL_ISSUES) * 50}")
    BAR=$(printf '█%.0s' $(seq 1 $BAR_LENGTH))

    echo "**${STATUS}**: ${COUNT} (${PERCENTAGE}%) ${BAR}" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## 📅 Weekly Breakdown

EOF

# Add weekly breakdown
for WEEK in $(echo "${!ISSUE_COUNT_BY_WEEK[@]}" | tr ' ' '\n' | sort -n); do
    COUNT=${ISSUE_COUNT_BY_WEEK[$WEEK]}
    echo "- **Week ${WEEK}**: ${COUNT} issue mentions" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## 🎯 Unique Issues Tracked This Quarter

Below are all unique Jira issues that appeared in your TODO lists during ${QUARTER_NAME}:

EOF

# List unique issues
for ISSUE in "${UNIQUE_ISSUES[@]}"; do
    echo "- [${ISSUE}](https://issues.redhat.com/browse/${ISSUE})" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## 📝 Detailed Weekly Logs

EOF

# Append weekly summaries
for WEEK_FILE in $(ls -1 "${WEEKLY_DIR}/week-"*"-${QUARTER_YEAR}.md" 2>/dev/null | sort); do
    WEEK_NAME=$(basename "$WEEK_FILE" .md)
    echo "### ${WEEK_NAME}" >> "$OUTPUT_FILE"
    cat "$WEEK_FILE" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<EOF

---

## 🎯 Quarterly Insights

### Productivity Patterns
- **Most Active Period**: Week $(for w in "${!ISSUE_COUNT_BY_WEEK[@]}"; do echo "${ISSUE_COUNT_BY_WEEK[$w]} $w"; done | sort -rn | head -1 | awk '{print $2}') with ${ISSUE_COUNT_BY_WEEK[$(for w in "${!ISSUE_COUNT_BY_WEEK[@]}"; do echo "${ISSUE_COUNT_BY_WEEK[$w]} $w"; done | sort -rn | head -1 | awk '{print $2}')]} issue mentions
- **Average Issues Per Week**: $(awk "BEGIN {printf \"%.1f\", $TOTAL_ISSUES / ${#ISSUE_COUNT_BY_WEEK[@]}}")
- **Focus Areas**: Based on ${UNIQUE_COUNT} unique issues tracked

### Recommendations for Next Quarter
1. Review long-standing "New" items (${NEW_ITEMS} items) - consider prioritization
2. Complete in-progress work (${IN_PROGRESS} items) before starting new initiatives
3. Maintain current velocity while focusing on issue closure

---

*Report generated by daily-jira-sync quarterly report tool*
EOF

echo ""
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Quarterly Report Generated${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}📊 ${QUARTER_NAME} Summary:${NC}"
echo -e "   Total Issue Mentions: ${TOTAL_ISSUES}"
echo -e "   Unique Issues: ${UNIQUE_COUNT}"
echo -e "   In Progress: ${IN_PROGRESS}"
echo ""
echo -e "${GREEN}📁 Report saved to: ${OUTPUT_FILE}${NC}"
echo ""
echo -e "${YELLOW}💡 Tip: Open the report with:${NC}"
echo -e "   ${BLUE}open ${OUTPUT_FILE}${NC}"
