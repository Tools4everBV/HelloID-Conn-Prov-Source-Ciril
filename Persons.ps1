# Getting variables from configuration tab
$config = ConvertFrom-Json $configuration
$dateReference = Get-Date $config.ReferenceDate

try{
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
    $OracleSQLQuery ="SELECT 
STR_NOSTR,
ExternalID,
MIN(StartDate) AS StartDate,
CASE 
    WHEN COUNT(*) != COUNT(EndDate) THEN NULL
    ELSE MAX(EndDate)
END AS EndDate,
MAX(STR_CHEMINLIB) AS STR_CHEMINLIB,
MAX(STR_CHEMINCODE) AS STR_CHEMINCODE,
MAX(STR_NO_MERE) AS STR_NO_MERE,
MAX(DAA_AA_NUM) AS DAA_AA_NUM,
MAX(Gender) AS Gender,
MAX(FamillyNamePartner) AS FamillyNamePartner,
MAX(FamillyName) AS FamillyName,
MAX(DAA_AG_NOMUSA) AS DAA_AG_NOMUSA,
MAX(GivenName) AS GivenName,
MAX(SecondGivenName) AS SecondGivenName,
MAX(Service) AS Service,
MAX(ServiceCode) AS ServiceCode,
MAX(ServiceName) AS ServiceName,
MAX(Status) AS Status,
MAX(TitleCode) AS TitleCode,
MAX(TitleName) AS TitleName,
MAX(ManagerExternalID) AS ManagerExternalID
FROM (
SELECT 
    STR_CHEMINLIB,
    STR_CHEMINCODE,
    STR_NOSTR,
    STR_NO_MERE,
    DAA_AA_NUM,
    DAA_AG_MATRI AS ExternalID,
    DAA_AA_DATDEB +1 AS StartDate,
    DAA_AA_DATFIN +1 AS EndDate,
    DAA_AG_TITRE AS Gender,         
    RTRIM(DAA_AG_NOMTRI) AS FamillyNamePartner,
    RTRIM(DAA_AG_NOMPAT) AS FamillyName,
    RTRIM(DAA_AG_NOMUSA) AS DAA_AG_NOMUSA,
    RTRIM(DAA_AG_PRENOM) AS GivenName,
    RTRIM(AG_SURNOM) AS SecondGivenName,
    RTRIM(STR_LIB) AS Service,
    STR_NOSTR AS ServiceCode,
    RTRIM(STR_LIBLON) AS ServiceName,
    DAA_EP_LIB AS Status,
    DAA_FI_NO AS TitleCode,
    RTRIM(DAA_FI_LIB_POS) AS TitleName,
    CASE 
        WHEN STR_RESP_MATRI = DAA_AG_MATRI THEN (
            SELECT MERE.STR_RESP_MATRI
            FROM GRHPROD_DAA.H_VUE_DEC_STRUC MERE
            WHERE MERE.STR_NOSTR = H_VUE_DEC_STRUC.STR_NO_MERE
        )
        ELSE STR_RESP_MATRI
    END AS ManagerExternalID
FROM GRHPROD_DAA.H_VUE_DAA
LEFT JOIN GRHPROD_DAA.H_VUE_DEC_STRUC 
    ON GRHPROD_DAA.H_VUE_DEC_STRUC.STR_NOSTR = GRHPROD_DAA.H_VUE_DAA.DAA_ST_NOSTR
LEFT JOIN GRHPROD_DAA.H_VUE_DEC_AGENT 
    ON GRHPROD_DAA.H_VUE_DEC_AGENT.AG_MATRI = GRHPROD_DAA.H_VUE_DAA.DAA_AG_MATRI
WHERE
    --DAA_AG_MATRI = 'XXXX' AND
    DAA_AA_NUMORD IS NOT NULL
    AND RTRIM(DAA_FI_LIB_POS) NOT LIKE 'VACATAIRE%'
    AND STR_CHEMINLIB IS NOT NULL
    AND STR_CHEMINCODE IS NOT NULL
) SUB
GROUP BY STR_NOSTR, TitleCode, ExternalID
ORDER BY STR_NOSTR, TitleCode, ExternalID
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
    $SelectDataTable = [System.Data.DataTable]::new()
    $SelectDataTable.Load($cmd.ExecuteReader())
    
    # Contract Table
    $Contracts = $SelectDataTable | group-object -Property ExternalID -AsHashTable -AsString
    
    # Persons Table 
    $persons = $SelectDataTable | sort-object FamillyName, GivenName, ExternalID -unique

   
    foreach($p in $persons){
        $person = @{}
        $person["ExternalId"] = $p.ExternalID
        $person["Gender"] = $p.Gender 
        $person["GivenName"] =  if($p.SecondGivenName -notlike ""){$p.SecondGivenName}else{$p.GivenName}
        $person["FamillyName"] = $p.FamillyName
        $person["FamillyNamePartner"] = $p.FamillyNamePartner
        $person["DisplayName"] = "$($p.FamillyNamePartner) $($p.GivenName) ($($p.ExternalID))"
        $person["Contracts"] = [System.Collections.ArrayList]@();
        
        foreach ($c in $Contracts["$($p.ExternalID)"]){
            $contract = @{}
            $contract["ID"] = $c["ExternalID"] + "-" + $c["DAA_AA_NUM"]
            $contract["StartDate"] = $c["StartDate"]
            $contract["EndDate"] = $c["EndDate"]
            $contract["TitleCode"] = $c["TitleCode"]
            $contract["TitleName"] = $c["TitleName"]
            $contract["DGAName"] = $c["STR_CHEMINLIB"].split('\')[4]
            $contract["DGACode"] = $c["STR_CHEMINCODE"].split('\')[4]
            $contract["DirectionName"] = $c["STR_CHEMINLIB"].split('\')[5]
            $contract["DirectionCode"] = $c["STR_CHEMINCODE"].split('\')[5]
            $contract["ServiceName"] = $c["STR_CHEMINLIB"].split('\')[6]
            $contract["ServiceCode"] = $c["STR_CHEMINCODE"].split('\')[6]
            $contract["TeamName"] = $c["STR_CHEMINLIB"].split('\')[7]
            $contract["TeamCode"] = $c["STR_CHEMINCODE"].split('\')[7]
            $contract["PoleName"] = $c["STR_CHEMINLIB"].split('\')[8]
            $contract["PoleCode"] = $c["STR_CHEMINCODE"].split('\')[8]
            $contract["OrganigrammePath"] = $c["STR_CHEMINLIB"]
            $contract["ManagerExternalID"] = $c["ManagerExternalID"]
            $contract["Status"] = $c["Status"]
            
            if($c.EndDate -Like ""){
                [void]$person.Contracts.Add($contract)
            }elseif($c.EndDate -gt $dateReference){
                [void]$person.Contracts.Add($contract)
            }
        }
        if($person.contracts){
            Write-Output ($person | ConvertTo-Json -Depth 50)
        }
    }
}
Catch{
    Write-error "Error when importing persons - $($_.Exception.Message)"
}
finally{
    if ($OracleConnection.State -eq 'Open') { $OracleConnection.close() }
}

