Import-Module SqlServer
Import-Module Get-NthDay

$current = Get-Date
$patch_tuesday = Get-NthDay -Ordinal 2 -Day Tuesday

$patch_tuesday_plus_two_days = $patch_tuesday.AddDays(2)

if(-not($current -ge $patch_tuesday_plus_two_days)){
    $current = (Get-date).AddMonths(-1)
}

$deployments = @{
    'servers'       = "('SVR - ADR Monthly Updates')"
    'workstations'  = "('WKS - ADR Monthly Updates - Ring 0 - Bravehearts','WKS - ADR Monthly Updates - Ring 1 - Enterprise Main')"
}

$patching = @{}

foreach( $deployment in $deployments.GetEnumerator() ) {

    $patching[$deployment.Name] = @{}

    foreach($timeframe in @{ 'current' = 0; 'previous' = -1}.GetEnumerator()){

        $data = @()

        $date       = $current.AddMonths($timeframe.Value)
        $datestamp  = $timeframe.Name
        

        $patching[$deployment.Name][$datestamp] = @{}

        $total_days = [DateTime]::DaysInMonth($date.Year, $date.Month)

        $start  = (Get-Date -Year $date.Year -Month $date.Month -Day 1).ToString('yyyy/MM/dd')
        $end    = (Get-Date -Year $date.Year -Month $date.Month -Day $total_days).ToString('yyyy/MM/dd')

        $description = $deployment.Value


        $query = "SELECT
            [vSMS_UpdatesAssignment].CollectionName,
            [vSMS_UpdatesAssignment].Description,
            [vSMS_UpdatesAssignment].AssignmentEnabled,
            [vSMS_UpdatesAssignment].EnforcementDeadline,
            [vSMS_SUMDeploymentStatistics].NumSuccess,
            [vSMS_SUMDeploymentStatistics].NumInProgress,
            [vSMS_SUMDeploymentStatistics].NumError,
            [vSMS_SUMDeploymentStatistics].NumReqsNotMet,
            [vSMS_SUMDeploymentStatistics].NumUnknown
        FROM
            [CM_LCF].[dbo].[vSMS_UpdatesAssignment]
            LEFT JOIN [CM_LCF].[dbo].[vSMS_SUMDeploymentStatistics] ON [vSMS_UpdatesAssignment].AssignmentID = [vSMS_SUMDeploymentStatistics].AssignmentID
        WHERE
            [vSMS_UpdatesAssignment].CreationTime between '{0}'
            and '{1}'
            and [vSMS_UpdatesAssignment].Description IN {2}
            ORDER BY CollectionName" -f $start, $end, $description

        $response = Invoke-Sqlcmd -ServerInstance "mecm.forsloff.local" -Query $query -TrustServerCertificate

        $successes  = 0
        $total      = 0
        $totals     = 0

        $patching[$deployment.Name][$datestamp]['phases'] = @()

        foreach($line in $response) {

            if($line.NumSuccess -is [DBNull]) {
                continue
            }

            $successes  += $line.NumSuccess 
            $totals     += ($total = ($line.NumSuccess + $line.NumInProgress + $line.NumError + $line.NumReqsNotMet + $line.NumUnknown))
            
            $decimal    = ($line.NumSuccess / $total)

            $compliance = 'non_compliant'
            
            if($decimal -eq 1) {
                $compliance = 'complete'
            } elseif(($decimal -lt 1) -and ($decimal -ge .95)) {
                $compliance = 'compliant'
            }

            $data += @{
                'name'          = $line.CollectionName
                'description'   = $line.Description
                'percentage'    = $decimal.ToString('P1')
                'deadline'      = ([Datetime]$line.EnforcementDeadline).GetDateTimeFormats()[44]
                'success'       = $line.NumSuccess
                'inprogress'    = $line.NumInProgress
                'error'         = $line.NumReqsNotMet
                'unknown'       = $line.NumUnknown
                'compliance'    = $compliance
            }

            $patching[$deployment.Name][$datestamp]['phases'] = $data

        }

        $decimal = $successes / $totals

        $patching[$deployment.Name][$datestamp]['percentage'] = $decimal.ToString('P1')
        $patching[$deployment.Name][$datestamp]['compliance'] = 'non_compliant'

        if($decimal -eq 1) {
            $patching[$deployment.Name][$datestamp]['compliance'] = 'complete'
        } elseif(($decimal -lt 1) -and ($decimal -ge .95)) {
            $patching[$deployment.Name][$datestamp]['compliance'] = 'compliant'
        }
    }

}

$patching | ConvertTo-Json -Depth 100 | Out-File '\\dashboards.forsloff.local\patching\data.json'