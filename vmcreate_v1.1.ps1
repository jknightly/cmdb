<# 
 
     .SYNOPSIS 
  
         vmcreate_v1.ps1 is an Azure Automation Powershell Runbook 
  
     .DESCRIPTION 
  
     This script recieves webhook data from OMS based on Azure Activity Logs recording a VM create 
     It will record the basic CMDB data and write it to the automation account output and to an azure storage table with the write-cmdbdata function     
 
 
    .EXAMPLE 
          This should be called by OMS based on an activity log search. See blogs.technet.microsoft.com/knightly 
 
     
 
    .NOTES 
 
   #> 


param([object]$webhookdata)

#confirm this is being called via webhook
if ($webhookdata -ne $null)
{
    
#these output writes are for debugging and understanding the webhook format
write-output $webhookdata.webhookname
Write-Output $webhookdata.requestheader
write-output $webhookdata.requestbody

#get data from the webhook request body
$cmdata = ConvertFrom-Json $WebhookData.RequestBody



#authenticate to azure with the runas account
    $connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
    
#collect VM information into variable
$x = 0 #this will increment on each $cmdata.searchresults.value in order to find all of the vms in the alert webhook
foreach ($value in $cmdata.searchresults.value)
{
    

if ($cmdata.searchresults.value[$x] -ne $null) {
    Write-Output "$x is the curent value of X" #this is for debugging
    #parse the json and get the vm information to variables
    $resourceID = $cmdata.searchresults.value.resourceID
    write-output $cmdata.searchresults.value.resource
    $vmname = $cmdata.searchresults.value.resource
    $rgname = $cmdata.searchresults.value.resourcegroup
    $subID = $cmdata.searchresults.value.subscriptionID 
    $caller = $cmdata.searchresults.value.caller
    write-output $vmname + 'in resource group ' + $rgname 'in sub' + $subID + 'was created'
    $subID = $subID.tostring()
    $resourceID = $cmdata.searchresults.value[$x].resourceID
    write-output $cmdata.searchresults.value[$x].resource
    $vmname = $cmdata.searchresults.value[$x].resource
    $rgname = $cmdata.searchresults.value[$x].resourcegroup
    $subID = $cmdata.searchresults.value[$x].subscriptionID 
    $caller = $cmdata.searchresults.value[$x].caller
    write-output $vmname + 'in resource group ' + $rgname 'in sub' + $subID + 'was created'
    $subID = $subID.tostring()
    
    #Collecting the basic virtual machine information
    Select-AzureRmSubscription -SubscriptionId $SubId
    $vminfo = Get-AzureRmvm -Name $vmname -ResourceGroupName $Rgname
    $vmsize = $vminfo.HardwareProfile.vmsize
    $nic = $vminfo.NetworkProfile.NetworkInterfaces
    $string = $nic.id.ToString()
    $nicname = $string.split("/")[-1]
    $ipconfig = Get-AzureRmNetworkInterface -ResourceGroupName $rgname -Name $nicname
    $ipconfig = $ipconfig.IpConfigurations.privateipaddress
    $name = $vminfo.Name
    $ostype = $vminfo.StorageProfile.OsDisk.OsType 
    $location = $vminfo.location
    $subname = Get-AzureRmSubscription
    $subname = $subname.SubscriptionName
    $a = get-date
    $date = $a.ToShortDateString()
    $time = $a.ToShortTimeString()
    $x++
     
    #writing output into the automation account
    write-output "$vmsize $Ipconfig $location $name $ostype $caller $timestamp"

    #once VM information is collected, it can be written into a storage table 
    Select-AzureRmSubscription -SubscriptionName 'sub1' #this should be the subscription that owns the storage account, not where the VM is deployed
    $resourceGroup = "OMSRG" #resource group that contains the storage table
    $storageAccount = "oamcmdbjk" #storage account that contains the table
    $tableName = "CMData"
    $saContext = (Get-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccount).Context
    $table = Get-AzureStorageTable -Name $tableName -Context $saContext 

 
    #search the storage table to see if the VM already exists
    [string]$filter1 = [Microsoft.WindowsAzure.Storage.Table.TableQuery]::GenerateFilterCondition("ResourceID", [Microsoft.WindowsAzure.Storage.Table.QueryComparisons]::Equal, "$resourceID")
    $new = Get-AzureStorageTableRowByCustomFilter -table $table -customFilter $filter1 
    if ($new -eq $null) {
        $partitionKey = "VMcreates"
        Add-StorageTableRow -table $table -partitionKey $partitionKey -rowKey ([guid]::NewGuid().tostring()) -property @{"SubscriptionName" = "$subname"; "SubscriptionID" = "$subid"; "ResourceGroup" = "$rgname"; "ResourceID" = "$resourceID"; "computerName" = "$vmname"; "ostype" = "$ostype"; "CreatorID" = "$caller"; "PrivateIP" = "$IPconfig"; "Location" = "$Location"; "VMSize" = "$VMsize"; "Date" = "$Date"; "Time" = "$Time"}
          
    }
    else {
        $partitionKey = "VMUpdates"
        Add-StorageTableRow -table $table -partitionKey $partitionKey -rowKey ([guid]::NewGuid().tostring()) -property @{"SubscriptionName" = "$subname"; "SubscriptionID" = "$subid"; "ResourceGroup" = "$rgname"; "ResourceID" = "$resourceID"; "computerName" = "$vmname"; "ostype" = "$ostype"; "CreatorID" = "$caller"; "PrivateIP" = "$IPconfig"; "Location" = "$Location"; "VMSize" = "$VMsize"; "Date" = "$Date"; "Time" = "$Time"}
          
    }

}} }
else {"Call this via webhook only"}


