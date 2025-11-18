Create a Jira issue from a GitHub PR with automatic effort estimation.

The script:
- Fetches PR details (title, changes, files, author)
- Estimates effort based on complexity (lines changed, files modified)
- Creates a Jira issue with effort tracking
- Adds a comment to the PR with the Jira link
- Logs the tracking data

Execute: `~/.claude/scripts/pr-to-jira.sh <PR-NUMBER> [--project PROJECT] [--type TYPE] [--severity LEVEL] [--story-points NUM] [--qe-applicable] [--auto]`

Examples:
- For current PR: `~/.claude/scripts/pr-to-jira.sh <number>`
- Create as Bug: `~/.claude/scripts/pr-to-jira.sh <number> --type Bug`
- Bug with severity and story points: `~/.claude/scripts/pr-to-jira.sh <number> --type Bug --severity Critical --story-points 1`
- Bug that requires QE testing: `~/.claude/scripts/pr-to-jira.sh <number> --type Bug --qe-applicable`
- Auto mode: `~/.claude/scripts/pr-to-jira.sh <number> --type Bug --auto`
- Different project: `~/.claude/scripts/pr-to-jira.sh <number> --project MGMT --type Bug`

Default settings:
- Activity Type:
  - "Quality / Stability / Reliability" (for Bugs)
  - "Product / Portfolio Work" (for Tasks/Stories)
- Severity: Important (applies to all types)
- Story Points: 0.5
- Labels:
  - GlobalHub (all types)
  - QE-NotApplicable (Bugs only, unless --qe-applicable flag is used)
- Affects/Fix Version: Global Hub 1.7.0
- Sprint: Current active GH Train sprint
- Status: Automatically moved to "In Progress"

After running, show the user the created Jira issue link and PR comment status.

Tracking logs are saved to: ~/Documents/daily-jira-sync/pr-tracking/
