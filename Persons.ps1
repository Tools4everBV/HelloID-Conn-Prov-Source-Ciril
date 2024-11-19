# Getting variables from configuration tab
$config = ConvertFrom-Json $configuration
Try{
    # Initializing Oracle connexion
    
    $config = ConvertFrom-Json $configuration;
    $count = 0
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
    $OracleSQLQuery = "WITH structure_path (st_nostr, st_lib, st_niveau, st_chemin) 
    AS(
        SELECT st_nostr, st_lib, 1, st_lib
        FROM h_struc_pos
        WHERE st_no_mere is NULL
    
        UNION all
    
        SELECT h.st_nostr, h.st_lib, sp.st_niveau + 1, sp.st_chemin || '/' || h.st_lib
        FROM h_struc_pos h
        JOIN structure_path sp on h.st_no_mere = sp.st_nostr
    )
    SELECT distinct DT_APPLI, 
    DT_NAISSANCE,
    H_AGT_INI.NOM,
    H_AGT_INI.PRENOM,
    substr(NO_MATRICULE,4,8) as NO_MATRICULE,
    AG_ADRURL as EMAIL_PERSO,
    DT_FIN_APPLI,
    (CASE WHEN H_VUE_RESP_HIE.MATRICULE IS NOT NULL THEN H_VUE_RESP_HIE.MATRICULE_RESPONSABLE ELSE NULL END) as MATRICULE_RESPONSABLE,
    H_VUE_RESP_HIE.POSTE,
    H_VUE_RESP_HIE.LIBELLE_POSTE,
    H_VUE_RESP_HIE.CODE_STRUCTURE,
    H_VUE_RESP_HIE.LIBELLE_STRUCTURE,
    istruct.st_chemin CHEMIN_STRUCTURE
    FROM H_AGT_INI
    LEFT JOIN H_VUE_RESP_HIE ON (concat('001', H_VUE_RESP_HIE.MATRICULE)) = H_AGT_INI.NO_MATRICULE
    LEFT JOIN structure_path istruct on istruct.st_nostr = H_VUE_RESP_HIE.CODE_STRUCTURE
    LEFT JOIN H_AGE on (concat('001', H_AGE.ag_matri)) = H_AGT_INI.NO_MATRICULE
    WHERE (DT_FIN_APPLI  > TO_DATE('01-01-24', 'DD-MM-YY') OR DT_FIN_APPLI IS NULL)
    AND substr(NO_MATRICULE,4,8) not in (
        SELECT distinct ag_matri
        FROM H_AGE
        WHERE ag_nomusa like '%NPU%'
    )
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
    $Contracts = $SelectDataTable
    # Persons Table 
    $persons = $SelectDataTable | sort-object NOM, PRENOM, NO_MATRICULE -unique

    foreach($p in $persons){
        $person = @{}
        $person["ExternalId"] = $p.NO_MATRICULE
        $person["FirstName"] = $p.PRENOM
        $person["LastName"] = $p.NOM
        $person["BirthDate"] = $p.DT_NAISSANCE
        $person["PersonalEmail"] = $p.EMAIL_PERSO
        $person["DisplayName"] = "$($p.NOM) $($p.PRENOM) ($($p.NO_MATRICULE))"
        $person["Contracts"] = [System.Collections.ArrayList]@();

        foreach ($c in $Contracts.Rows){
            if ( $c["NO_MATRICULE"] -eq $p.NO_MATRICULE){
                $contract = @{}
                $contract["ID"] = $c["NO_MATRICULE"] + $c["POSTE"] + $c["MATRICULE_RESPONSABLE"] + "-" + $c["DT_APPLI"]
                $contract["StartDate"] = $c["DT_APPLI"]
                $contract["EndDate"] = $c["DT_FIN_APPLI"]
                $contract["NumeroPoste"] = $c["POSTE"]
                $contract["LibellePoste"] = $c["LIBELLE_POSTE"]
                $contract["CodeStructure"] = $c["CODE_STRUCTURE"]
                $contract["LibelleStructure"] = $c["LIBELLE_STRUCTURE"]
                $contract["MatriculeResponsable"] = $c["MATRICULE_RESPONSABLE"]
                $contract["CheminCompletStructure"] = $c["CHEMIN_STRUCTURE"]

                [void]$person.Contracts.Add($contract)
            }
        }
    }
    Write-Output ($person | ConvertTo-Json -Depth 50)
}
Catch{
    Write-error "Error when importing persons - $($_.Exception.Message)"
}
finally{
    if ($OracleConnection.State -eq 'Open') { $OracleConnection.close() }
}