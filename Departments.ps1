$config = ConvertFrom-Json $configuration
try {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Data.OracleClient") | out-null
    # Creating a new object
    $conn = [System.Data.Odbc.OdbcConnection]::new()
    $conn.connectionstring = $config.dsn
    $conn.open()

    # Querying UF
    $sql = "SELECT DISTINCT * FROM UFP"
    $cmd = [System.Data.Odbc.OdbcCommand]::new($sql, $conn)
    $da = [System.Data.Odbc.OdbcDataAdapter]::new($cmd)
    $dt = [System.Data.datatable]::new()
    $null = $da.fill($dt)
    $departments += $dt
    $departments = $departments  | Select-Object -Property * -ExcludeProperty RowError,RowState,Table,ItemArray,HasErrors
    $conn.close()

    $result = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach($item in $departments){
        $department = @{
            ExternalId  = $item.NUFPUF
            DisplayName = $item.LBRPUF
            Name        = $item.LBRPUF
        }
        $result.Add($department)
        Write-Output ($department | ConvertTo-Json -Depth 50)
    }
    Write-information "$($result.count) departements imported"
}catch{
    
    Write-error "Error during UF importation - $($_.Exception.Message)"
}
