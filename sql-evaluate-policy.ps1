<# input variables, pass servers as an array i.e. "server1", "server2", "serverN" #>
[string[]]$servers = "localhost"

<# location where the xml policies are kept #>
[string]$policypath = "C:\sql-policy\"

<# CSS prettyfying for the output HTML #>
[string]$HtmlHead = 
@"
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Policy evaluation $(Get-Date)</title>
</head>
<style type="text/css">
    h1, h5, th { text-align: center; }
    table { margin: left; font-family: Segoe UI; border: thin ridge grey; margin:0px 5px 5px 0px; }
    th { font-size: 10px; background: #7f8184; color: #fff; padding: 5px 5px; }
    td { font-size: 9px; padding: 5px 20px; color: #000; }
    tr { background: #b8d1f3; }
    tr:hover td {}
    tr:nth-child(even) { background: #ededed; }
    tr:nth-child(odd) { background: #fcfcfc; }

    th.Server, th.Date, th.Policy, th.Object, th.Result {max-width: 200px;}
    th.Exception {width: 40px;}
</style>
"@

<# Set action to perform; CHECK=check only, CONFIGURE=Policy settings will be applied to the server, careful in PROD 
   Evaluation will only happen for the type of policy specified here, policy files (xml) have action in the file name
   to allow this to happen. This is because whilst we can run CONFIGURE policies in CHECK mode will work fine but not
   the other way round i.e. ENFORCING check only policies will cause errors #>
$Action="Check"

<# pipe output for better memory management. in powershell foreach loads all results into memory whilst piping does not.
this means foreach is faster but uses much more memory whilst piping is slower but much more memory friendly. since we are
potentially crawlinlg through a lot of data this could result in large data sets. #>

<# we have our $servers array populated with servers in scope for evaluation, lets iterate through these #>
$servers | %{
            $TargetServerName = $_
            <# get policies in xml files and pipe into Invoke-POlicyEvaluation #>
            Get-ChildItem -Path $policypath -Filter "Policy-Check-*.xml" | %{
            #https://docs.microsoft.com/en-us/powershell/module/sqlps/invoke-policyevaluation?view=sqlserver-ps
            $_ | Invoke-PolicyEvaluation -AdHocPolicyEvaluationMode $Action -TargetServerName $TargetServerName 
            }
    } | %{
            $PolicyName = $_.PolicyName
            $Date = $_.EndDate
            <# now iterate through all evaluated objects and get evaluation details #>
            $_ | ?{$_.PolicyName -eq $PolicyName} | Select -ExpandProperty ConnectionEvaluationHistories | Select -ExpandProperty EvaluationDetails | Select * | Select `
                <# set "columns", these will be returned as PS object #>
                @{Name="Evaluated Server";Expression={$_.Parent.ServerInstance}}, `
                @{Name="Evaluation Date";Expression={$Date}}, `
                @{Name="Policy Name";Expression={$PolicyName}}, `
                @{Name="Evaluated Object";Expression={$_.TargetQueryExpression}}, `
                @{Name="Results";Expression={if ($_.Exception) {"ERROR"} elseif($_.Result -eq $False){"FAIL"} else {"PASS"}}}, `
                @{Name="Exception";Expression={$_.Exception -split "---> " -split "Microsoft.SqlServer.Management." -split " at " | ?{$_ -like "*Exception*" -and $_ -notlike "*End of inner exception stack trace*" -and $_ -notlike "System.Reflection.*"}}}
            } | Sort "Evaluated Server", "Policy Name", "Evaluated Object", "Results" | 
    <# extract results to HTML file, at this poitn we can insert into a table #>
    ConvertTo-Html -Head $HtmlHead | %{$_ `
    <# set RAG colors #> `
    -replace "<td>ERROR</td>","<td bgcolor=`"#ff6b6b`">ERROR</td>" `
    -replace "<td>FAIL</td>","<td bgcolor=`"#efcb02`">FAIL</td>" `
    -replace "<td>PASS</td>","<td bgcolor=`"#02ef7c`">PASS</td>" `
    <# add classess to columns #> `
    -replace "<th>Evaluated Server</th>","<th class=`"Server`">Evaluated Server</th>" `
    -replace "<th>Evaluation Date</th>", "<th class=`"Date`">Evaluation Date</th>" `
    -replace "<th>Policy Name</th>", "<th class=`"Policy`">Policy Name</th>" `
    -replace "<th>Evaluated Object</th>", "<th class=`"Object`">Evaluated Object</th>" `
    -replace "<th>Results</th>", "<th class=`"Result`">Results</th>" `
    -replace "<th>Exception</th>", "<th class=`"Exception`">Exception</th>" `
    } | Out-File -FilePath "$policypath\Result.html"
