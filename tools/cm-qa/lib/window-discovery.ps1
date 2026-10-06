Set-StrictMode -Version Latest

function Select-CmQaWindowCandidate {
    param([object[]]$Candidates)

    $eligible = @($Candidates | Where-Object {
        $_.accepted -eq $true -and
        $_.visible -eq $true -and
        [int]$_.clientWidth -ge 320 -and
        [int]$_.clientHeight -ge 200
    })
    if ($eligible.Count -eq 0) {
        return [ordered]@{ status='CLIENT_DRIVER_BLOCKED_FIVEM_WINDOW_NOT_FOUND'; selected=$null; candidates=@($Candidates) }
    }

    $maxScore = [int](($eligible | Measure-Object -Property score -Maximum).Maximum)
    $top = @($eligible | Where-Object { [int]$_.score -eq $maxScore })
    if ($top.Count -ne 1) {
        return [ordered]@{ status='CLIENT_DRIVER_BLOCKED_AMBIGUOUS_FIVEM_WINDOW'; selected=$null; candidates=@($Candidates) }
    }
    return [ordered]@{ status='CLIENT_WINDOW_FOUND'; selected=$top[0]; candidates=@($Candidates) }
}
