BeforeAll {
    $logLevel = "off"
    $SCRIPT_PATH = Join-Path $TestDrive "Test.ps1"
    . "$PSScriptRoot/../../Winspect/src/Constants.ps1"
    . "$PSScriptRoot/../../Winspect/src/Logging.ps1"
    . "$PSScriptRoot/../../Winspect/src/Utilities.ps1"
    . "$PSScriptRoot/../src/Constants.ps1"
    . "$PSScriptRoot/../src/ScheduledTaskInfo.ps1"

    function New-FakeTask($taskName, $arguments, $userId, $daysOfWeek, $startBoundary, $weeksInterval = 1) {
        $action = [pscustomobject]@{ Arguments = $arguments }
        $trigger = [pscustomobject]@{ DaysOfWeek = $daysOfWeek; StartBoundary = $startBoundary; WeeksInterval = $weeksInterval }
        $principal = [pscustomobject]@{ UserId = $userId }
        return [pscustomobject]@{
            TaskName  = $taskName
            Actions   = @($action)
            Triggers  = @($trigger)
            Principal = $principal
        }
    }
}

Describe "Get-Weekdays" {
    It "reports Daily when no DaysOfWeek bitmask is given" {
        Get-Weekdays $null | Should -Be "Daily"
    }

    It "resolves a single-day bitmask to that day's name" {
        Get-Weekdays 1 | Should -Be "Sunday"   # bit 0
        Get-Weekdays 64 | Should -Be "Saturday" # bit 6
    }

    It "resolves a multi-day bitmask to a comma-joined list in day order" {
        # Monday (2) + Wednesday (8) + Friday (32)
        Get-Weekdays (2 + 8 + 32) | Should -Be "Monday, Wednesday, Friday"
    }
}

Describe "Get-RestartTimeOfDay" {
    It "extracts the HH:mm portion from an ISO 8601 timestamp" {
        Get-RestartTimeOfDay "2023-08-08T04:00:00+00:00" | Should -Be "04:00"
    }
}

Describe "Get-ScheduledRestartTask" {
    It "returns null when no matching task exists, without throwing" {
        Mock Get-ScheduledTask {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("No task found"),
                "CmdletizationQuery_NotFound_TaskName,Get-ScheduledTask",
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $null
            )
            throw $errorRecord
        }

        Get-ScheduledRestartTask | Should -BeNullOrEmpty
    }

    It "re-throws any other failure rather than silently treating it as 'not found'" {
        Mock Get-ScheduledTask {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Access denied"),
                "SomeOtherError,Get-ScheduledTask",
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null
            )
            throw $errorRecord
        }

        { Get-ScheduledRestartTask } | Should -Throw
    }

    It "returns the real task object when one is found" {
        # The fake task is constructed directly inside the Mock body, not referenced from an outer
        # variable - Winspect's own test suite never references an It-block-local variable from
        # inside a Mock body either, and this codebase's mock scriptblocks aren't a proven-reliable
        # closure over that outer scope.
        Mock Get-ScheduledTask { New-FakeTask "Restart-Saga" ".\stop-saga.ps1" "ayfie" $null "2026-01-01T04:00:00Z" }

        (Get-ScheduledRestartTask).TaskName | Should -Be "Restart-Saga"
    }
}

Describe "Get-ScheduledRestartSummary" {
    It "reports every field as 'No scheduled restart' when the task is null" {
        $summary = Get-ScheduledRestartSummary $null

        $summary.TaskName | Should -Be $RESTART_TASK_NAME
        $summary.ExecutionTime | Should -Be $NO_SCHEDULED_TASK
        $summary.Command | Should -Be $NO_SCHEDULED_TASK
        $summary.User | Should -Be $NO_SCHEDULED_TASK
    }

    It "formats a daily trigger as 'Daily at <time>'" {
        $task = New-FakeTask "Restart-Saga" ".\stop-saga.ps1" "ayfie" $null "2026-01-01T04:00:00Z"
        $summary = Get-ScheduledRestartSummary $task

        $summary.ExecutionTime | Should -Be "Daily at 04:00"
        $summary.Command | Should -Be ".\stop-saga.ps1"
        $summary.User | Should -Be "ayfie"
    }

    It "formats a weekly trigger (WeeksInterval 1) as 'Every <day> at <time>'" {
        $task = New-FakeTask "Restart-Saga" ".\stop-saga.ps1" "ayfie" 1 "2026-01-04T04:00:00Z" 1
        $summary = Get-ScheduledRestartSummary $task

        $summary.ExecutionTime | Should -Be "Every Sunday at 04:00"
    }

    It "formats a multi-week trigger as '<day> at <time> every N weeks'" {
        $task = New-FakeTask "Restart-Saga" ".\stop-saga.ps1" "ayfie" 1 "2026-01-04T04:00:00Z" 2
        $summary = Get-ScheduledRestartSummary $task

        $summary.ExecutionTime | Should -Be "Sunday at 04:00 every 2 weeks"
    }
}
