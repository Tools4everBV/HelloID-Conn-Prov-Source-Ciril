# Getting variables from configuration tab
$config = ConvertFrom-Json $configuration
Try{
    # Initializing Oracle connexion
    Add-Type -Path $config.DLLPath
 
    ## connection string ###
    $dataSource = @"
    (DESCRIPTION =
        (LOAD_BALANCE = yes)
        (FAILOVER = yes)
        (ADDRESS =
            (PROTOCOL = TCP)
            (HOST = $($config.Host))
            (PORT = $($config.Port))
        )
        (CONNECT_DATA =
            (SERVICE_NAME = $($config.ServiceName))
            (FAILOVER_MODE =
                (TYPE = SELECT)
                (METHOD = BASIC)
                (RETRIES = 300)
                (DELAY = 2)
            )
        )
    )
"@   
    # Querying SQL
    $OracleSQLQuery ="
    SELECT DISTINCT
    H_VUE_RESP_HIE.CODE_STRUCTURE,
    H_VUE_RESP_HIE.LIBELLE_STRUCTURE
    FROM H_VUE_RESP_HIE
    "
    ### open up oracle connection to database ###
    $connectionString = "User Id=$($config.username);Password=$($config.password);Data Source=$dataSource"
    $con = [Oracle.ManagedDataAccess.Client.OracleConnection]::new($connectionString)
    $con.Open()
    
    ### create object ###
    $cmd = $con.CreateCommand()
    $cmd.CommandType = [System.Data.CommandType]::Text
    
    ### create datatable and load results into datatable ###
    $cmd.CommandText = $OracleSQLQuery
    $Departments = [System.Data.DataTable]::new()
    $Departments.Load($cmd.ExecuteReader())
    foreach($item in $departments){
        $department = @{
            ExternalId  = $item.CODE_STRUCTURE
            DisplayName = $item.LIBELLE_STRUCTURE
            Name        = $item.LIBELLE_STRUCTURE
        }
        $result.Add($department)
        Write-Output ($department | ConvertTo-Json -Depth 50)
    }
    Write-information "$($result.count) departements imported"
}
Catch{
    Write-error "Error when importing persons - $($_.Exception.Message)"
}
finally{
    if ($OracleConnection.State -eq 'Open') { $OracleConnection.close() }
}