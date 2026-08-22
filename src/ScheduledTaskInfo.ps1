function Get-Weekdays($daysOfWeekNumber) {
    Write-FunctionCallLog $PSBoundParameters
    if ($null -eq $daysOfWeekNumber) {
        $weekdays = "Daily"
    } else {
        # Task Scheduler's DaysOfWeek bitmask: bit N (value 2^N) = day N, Sunday=0..Saturday=6.
        $days = @()
        for ($bit = 0; $bit -le 6; $bit++) {
            if ($daysOfWeekNumber -band (1 -shl $bit)) {
                $days += [DayOfWeek]$bit
            }
        }
        $weekdays = $days -join ", "
    }
    Write-ReturnValue $weekdays
}

function Get-RestartTimeOfDay($iso8601DateString) {
    Write-FunctionCallLog $PSBoundParameters
    Write-ReturnValue $iso8601DateString.Substring(11, 5)
}

function Get-ScheduledRestartTask() {
    Write-FunctionCallLog $PSBoundParameters
    $task = $null
    try {
        $task = Get-ScheduledTask -TaskName $RESTART_TASK_NAME -ErrorAction Stop
    } catch {
        # Task not found is the expected "no restart scheduled" case, not a real error worth
        # surfacing - any other failure (e.g. the ScheduledTasks module missing) still throws.
        # Matched on FullyQualifiedErrorId, not the exception message text - confirmed on a
        # PT-localized Windows install that the message itself is localized ("Nenhum objeto
        # MSFT_ScheduledTask encontrado..."), which silently broke an earlier English-text-matching
        # version of this check (it re-threw the expected "not found" case as a real failure).
        if ($_.FullyQualifiedErrorId -ne "CmdletizationQuery_NotFound_TaskName,Get-ScheduledTask") {
            throw
        }
    }
    Write-ReturnValue $task
}

function Get-ScheduledRestartSummary($task) {
    Write-FunctionCallLog $PSBoundParameters
    if ($null -eq $task) {
        $summary = [PSCustomObject]@{
            TaskName      = $RESTART_TASK_NAME
            ExecutionTime = $NO_SCHEDULED_TASK
            Command       = $NO_SCHEDULED_TASK
            User          = $NO_SCHEDULED_TASK
        }
    } else {
        $trigger = $task.Triggers | Select-Object -First 1
        $action = $task.Actions | Select-Object -First 1
        if ($null -eq $trigger) {
            $executionTime = "Unknown schedule"
        } else {
            $weekdays = Get-Weekdays $trigger.DaysOfWeek
            $timeOfDay = Get-RestartTimeOfDay $trigger.StartBoundary
            if ($weekdays -eq "Daily") {
                $executionTime = "Daily at $timeOfDay"
            } elseif ($trigger.WeeksInterval -eq 1) {
                $executionTime = "Every $weekdays at $timeOfDay"
            } else {
                $executionTime = "$weekdays at $timeOfDay every $($trigger.WeeksInterval) weeks"
            }
        }
        $summary = [PSCustomObject]@{
            TaskName      = $task.TaskName
            ExecutionTime = $executionTime
            Command       = $action.Arguments
            User          = $task.Principal.UserId
        }
    }
    Write-ReturnValue $summary
}
