Run the daily Jira sync script to fetch today's Jira issues and display them as a TODO list.

The script automatically:
- Displays formatted TODO list in console
- Saves to local file (daily + weekly aggregation) in ~/Documents/daily-jira-sync/
- Sends to Slack (if SLACK_WEBHOOK_URL environment variable is set)

Execute: `~/.claude/scripts/daily-jira-sync.sh`

After running, offer to help the user update any issues or take actions based on the TODO list.
