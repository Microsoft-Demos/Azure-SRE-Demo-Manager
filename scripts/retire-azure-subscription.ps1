#requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,

    [ValidateSet('Assess', 'RemoveRepositoryResources', 'CancelSubscription')]
    [string]$Action = 'Assess',

    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Environment = 'dev',

    [string]$ConfirmSubscriptionId,

    [switch]$GitHubNetworkConfigurationRemoved,

    [switch]$ExternalContextRemoved,

    [ValidateRange(1, 120)]
    [int]$WaitTimeoutMinutes = 30,

    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments --only-show-errors --output json 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | Out-String).Trim()

    if ($exitCode -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')`n$text"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    return $text | ConvertFrom-Json
}

function Invoke-AzNoOutput {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & az @Arguments --only-show-errors --output none 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')`n$(($output | Out-String).Trim())"
    }
}

function Test-AzGroupExists {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $output = & az group exists `
        --name $Name `
        --subscription $SubscriptionId `
        --only-show-errors `
        --output tsv 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check resource group '$Name': $(($output | Out-String).Trim())"
    }

    return (($output | Out-String).Trim() -eq 'true')
}

function Get-RepositoryResourceGroupNames {
    return @(
        "rg-parking-frontend-$Environment"
        "rg-parking-lisbon-$Environment"
        "rg-parking-berlin-$Environment"
        "rg-parking-berlin-mcp-$Environment"
        "rg-parking-chaos-$Environment"
        "rg-parking-madrid-$Environment"
        "rg-parking-paris-$Environment"
        "rg-parking-hub-$Environment"
    )
}

function Get-RetirementAssessment {
    $scope = "/subscriptions/$SubscriptionId"
    $subscription = Invoke-AzJson @(
        'account', 'show',
        '--subscription', $SubscriptionId
    )
    $resourceGroups = @(Invoke-AzJson @(
        'group', 'list',
        '--subscription', $SubscriptionId
    ))
    $resources = @(Invoke-AzJson @(
        'resource', 'list',
        '--subscription', $SubscriptionId
    ))
    $locks = @(Invoke-AzJson @(
        'lock', 'list',
        '--subscription', $SubscriptionId
    ))
    $budgets = @(Invoke-AzJson @(
        'consumption', 'budget', 'list',
        '--subscription', $SubscriptionId
    ))
    $policyAssignments = @(Invoke-AzJson @(
        'policy', 'assignment', 'list',
        '--scope', $scope,
        '--subscription', $SubscriptionId
    ))
    $roleAssignments = @(Invoke-AzJson @(
        'role', 'assignment', 'list',
        '--scope', $scope,
        '--subscription', $SubscriptionId
    ))
    $customRoles = @(
        @(Invoke-AzJson @(
            'role', 'definition', 'list',
            '--custom-role-only', 'true',
            '--subscription', $SubscriptionId
        )) | Where-Object {
            $assignableScopes = @($_.assignableScopes)
            @($assignableScopes | Where-Object {
                $candidateScope = ([string]$_).TrimEnd('/')
                $candidateScope.Equals($scope, [StringComparison]::OrdinalIgnoreCase) -or
                $candidateScope.StartsWith("$scope/", [StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0
        }
    )

    $expectedGroups = @(Get-RepositoryResourceGroupNames)
    $expectedLookup = @{}
    foreach ($name in $expectedGroups) {
        $expectedLookup[$name.ToLowerInvariant()] = $true
    }

    $managedRepositoryGroups = @($resourceGroups | Where-Object {
        $managedByProperty = $_.PSObject.Properties['managedBy']
        $managedBy = if ($null -eq $managedByProperty) { '' } else { [string]$managedByProperty.Value }
        if ([string]::IsNullOrWhiteSpace($managedBy)) {
            return $false
        }

        foreach ($expectedName in $expectedGroups) {
            if ($managedBy -match "/resourceGroups/$([regex]::Escape($expectedName))/") {
                return $true
            }
        }

        return $false
    })

    $managedLookup = @{}
    foreach ($group in $managedRepositoryGroups) {
        $managedGroupName = ([string]$group.name).ToLowerInvariant()
        $managedLookup[$managedGroupName] = $true
    }

    $presentRepositoryGroups = @($resourceGroups | Where-Object {
        $expectedLookup.ContainsKey(([string]$_.name).ToLowerInvariant())
    })
    $unexpectedGroups = @($resourceGroups | Where-Object {
        $name = ([string]$_.name).ToLowerInvariant()
        -not $expectedLookup.ContainsKey($name) -and -not $managedLookup.ContainsKey($name)
    })
    $recoveryVaults = @($resources | Where-Object {
        $_.type -ieq 'Microsoft.RecoveryServices/vaults'
    })
    $githubNetworkSettings = @($resources | Where-Object {
        $_.type -ieq 'GitHub.Network/networkSettings'
    })
    $resourcesByGroup = @($resources |
        Group-Object -Property resourceGroup |
        Sort-Object -Property Name |
        ForEach-Object {
            [pscustomobject]@{
                resourceGroup = $_.Name
                resourceCount = $_.Count
            }
        })

    $readyForCancellation = (
        $resources.Count -eq 0 -and
        $resourceGroups.Count -eq 0 -and
        $locks.Count -eq 0 -and
        $customRoles.Count -eq 0
    )

    return [pscustomobject]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        subscription = [pscustomobject]@{
            id = $subscription.id
            name = $subscription.name
            state = $subscription.state
            tenantId = $subscription.tenantId
        }
        action = $Action
        environment = $Environment
        readyForCancellation = $readyForCancellation
        resourceCount = $resources.Count
        resourceGroupCount = $resourceGroups.Count
        lockCount = $locks.Count
        directRoleAssignmentCount = $roleAssignments.Count
        policyAssignmentCount = $policyAssignments.Count
        budgetNames = @($budgets | ForEach-Object { $_.name })
        customRolesReferencingSubscription = @($customRoles | ForEach-Object { $_.roleName })
        expectedRepositoryResourceGroups = $expectedGroups
        presentRepositoryResourceGroups = @($presentRepositoryGroups | ForEach-Object { $_.name })
        managedRepositoryResourceGroups = @($managedRepositoryGroups | ForEach-Object { $_.name })
        unexpectedResourceGroups = @($unexpectedGroups | ForEach-Object {
            $managedByProperty = $_.PSObject.Properties['managedBy']
            [pscustomobject]@{
                name = $_.name
                location = $_.location
                managedBy = if ($null -eq $managedByProperty) { $null } else { $managedByProperty.Value }
            }
        })
        recoveryServicesVaults = @($recoveryVaults | ForEach-Object {
            [pscustomobject]@{
                name = $_.name
                resourceGroup = $_.resourceGroup
                id = $_.id
            }
        })
        githubNetworkSettings = @($githubNetworkSettings | ForEach-Object {
            [pscustomobject]@{
                name = $_.name
                resourceGroup = $_.resourceGroup
                id = $_.id
            }
        })
        resourcesByGroup = $resourcesByGroup
    }
}

function Write-Assessment {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Assessment
    )

    $json = $Assessment | ConvertTo-Json -Depth 8
    Write-Output $json

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $parent = Split-Path -Parent $ReportPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            throw "Report directory does not exist: $parent"
        }

        Set-Content -LiteralPath $ReportPath -Value $json -Encoding utf8NoBOM
    }
}

function Assert-ExplicitConfirmation {
    if ($ConfirmSubscriptionId -ne $SubscriptionId) {
        throw 'ConfirmSubscriptionId must exactly match SubscriptionId for destructive actions.'
    }
}

function Assert-UnconditionedOwner {
    $account = Invoke-AzJson @(
        'account', 'show',
        '--subscription', $SubscriptionId
    )
    if ($account.user.type -ine 'user') {
        throw 'Subscription cancellation requires an interactive user with an unconditioned Owner role.'
    }

    $user = Invoke-AzJson @('ad', 'signed-in-user', 'show')
    $assignments = @(Invoke-AzJson @(
        'role', 'assignment', 'list',
        '--assignee-object-id', $user.id,
        '--scope', "/subscriptions/$SubscriptionId",
        '--include-inherited',
        '--include-groups',
        '--subscription', $SubscriptionId
    ))
    $ownerAssignments = @($assignments | Where-Object {
        $_.roleDefinitionName -eq 'Owner' -and
        [string]::IsNullOrWhiteSpace([string]$_.condition)
    })

    if ($ownerAssignments.Count -eq 0) {
        throw 'The signed-in user does not have the unconditioned Owner role required to cancel this subscription.'
    }
}

function Wait-ForResourceGroupDeletion {
    param(
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $deadline = [DateTime]::UtcNow.AddMinutes($WaitTimeoutMinutes)
    $remaining = @($Names)

    while ($remaining.Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw "Timed out waiting for resource groups to delete: $($remaining -join ', ')"
        }

        Start-Sleep -Seconds 15
        $remaining = @($remaining | Where-Object { Test-AzGroupExists -Name $_ })
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required.'
}

$assessment = Get-RetirementAssessment

switch ($Action) {
    'Assess' {
        Write-Assessment -Assessment $assessment
        break
    }

    'RemoveRepositoryResources' {
        Assert-ExplicitConfirmation
        Write-Assessment -Assessment $assessment

        if ($assessment.githubNetworkSettings.Count -gt 0 -and -not $GitHubNetworkConfigurationRemoved) {
            throw 'Remove the GitHub organization network configuration first, then rerun with -GitHubNetworkConfigurationRemoved.'
        }

        foreach ($setting in @($assessment.githubNetworkSettings)) {
            if ($assessment.presentRepositoryResourceGroups -contains $setting.resourceGroup) {
                if ($PSCmdlet.ShouldProcess($setting.id, 'Delete GitHub network settings resource')) {
                    Invoke-AzNoOutput @(
                        'resource', 'delete',
                        '--ids', $setting.id,
                        '--subscription', $SubscriptionId
                    )
                }
            }
        }

        $repositoryGroups = @(Get-RepositoryResourceGroupNames)
        $hubGroup = "rg-parking-hub-$Environment"
        $dependentGroups = @($repositoryGroups | Where-Object { $_ -ne $hubGroup })
        $startedDependentGroups = @()

        foreach ($groupName in $dependentGroups) {
            if ($assessment.presentRepositoryResourceGroups -contains $groupName) {
                if ($PSCmdlet.ShouldProcess($groupName, 'Delete repository resource group')) {
                    Invoke-AzNoOutput @(
                        'group', 'delete',
                        '--name', $groupName,
                        '--subscription', $SubscriptionId,
                        '--yes',
                        '--no-wait'
                    )
                    $startedDependentGroups += $groupName
                }
            }
        }

        if ($startedDependentGroups.Count -gt 0) {
            $dependentWaitGroups = @(
                $startedDependentGroups
                $assessment.managedRepositoryResourceGroups
            ) | Sort-Object -Unique
            Wait-ForResourceGroupDeletion -Names $dependentWaitGroups
        }

        $remainingDependentGroups = @(
            @(
                $dependentGroups
                $assessment.managedRepositoryResourceGroups
            ) | Sort-Object -Unique | Where-Object { Test-AzGroupExists -Name $_ }
        )
        if ($remainingDependentGroups.Count -gt 0) {
            throw "Hub deletion refused while dependent resource groups remain: $($remainingDependentGroups -join ', ')"
        }

        $hubDeletionStarted = $false
        if ($assessment.presentRepositoryResourceGroups -contains $hubGroup) {
            if ($PSCmdlet.ShouldProcess($hubGroup, 'Delete repository hub resource group')) {
                Invoke-AzNoOutput @(
                    'group', 'delete',
                    '--name', $hubGroup,
                    '--subscription', $SubscriptionId,
                    '--yes',
                    '--no-wait'
                )
                $hubDeletionStarted = $true
            }
        }

        if ($hubDeletionStarted) {
            Wait-ForResourceGroupDeletion -Names @($hubGroup)
        }

        Write-Assessment -Assessment (Get-RetirementAssessment)
        break
    }

    'CancelSubscription' {
        Assert-ExplicitConfirmation
        Write-Assessment -Assessment $assessment

        if (-not $assessment.readyForCancellation) {
            throw "Cancellation refused: $($assessment.resourceCount) resources, $($assessment.resourceGroupCount) resource groups, $($assessment.lockCount) locks, and $($assessment.customRolesReferencingSubscription.Count) custom role dependencies remain."
        }
        if (-not $ExternalContextRemoved) {
            throw 'Cancellation refused until GitHub credentials, runners/networking, and dedicated Entra principals have been removed. Rerun with -ExternalContextRemoved after completing the runbook.'
        }

        if ($PSCmdlet.ShouldProcess($SubscriptionId, 'Cancel Azure subscription')) {
            Assert-UnconditionedOwner
            $null = Invoke-AzJson @('extension', 'show', '--name', 'account')

            $finalAssessment = Get-RetirementAssessment
            Write-Assessment -Assessment $finalAssessment
            if (-not $finalAssessment.readyForCancellation) {
                throw "Cancellation refused after final assessment: $($finalAssessment.resourceCount) resources, $($finalAssessment.resourceGroupCount) resource groups, $($finalAssessment.lockCount) locks, and $($finalAssessment.customRolesReferencingSubscription.Count) custom role dependencies remain."
            }

            Invoke-AzNoOutput @(
                'account', 'subscription', 'cancel',
                '--subscription-id', $SubscriptionId,
                '--yes'
            )
        }
        break
    }
}
