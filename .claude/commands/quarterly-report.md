Generate a quarterly report from daily Jira sync data.

The script aggregates all weekly logs for the specified quarter and generates:
- Key metrics and statistics
- Status distribution
- Weekly breakdown
- Unique issues tracked
- Productivity insights and recommendations

Execute: `~/.claude/scripts/generate-quarterly-report.sh [YYYY-QN]`

Examples:
- Current quarter: `~/.claude/scripts/generate-quarterly-report.sh`
- Specific quarter: `~/.claude/scripts/generate-quarterly-report.sh 2025-Q4`

After running, show the user the location of the generated report and offer to open it.

Reports are saved to: ~/Documents/daily-jira-sync/quarterly/
