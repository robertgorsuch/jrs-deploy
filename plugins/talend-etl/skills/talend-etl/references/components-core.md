# Core component families: Database, File, Processing, schema and data types (Standard Jobs)

> Verification: doc-derived (help.qlik.com / help.talend.com search snippets, Talend GitHub, Maven Central) plus model knowledge. Not exercised against a live Studio/TAC/TMC in this build. Items marked (unverified) are from memory only and should be checked in Studio before relying on exact labels.

Scope: Standard (Data Integration) Jobs only. Not here: tMap/tXMLMap/tELTMap expression
internals (tmap-expressions.md), Orchestration/Logs/Misc/System (orchestration-logging.md),
cloud/SaaS/NoSQL/messaging connectors incl. BigQuery, Databricks, Hive (connectors-catalog.md,
big-data-spark.md), Spark components (big-data-spark.md), DQ components (data-quality-governance.md).

## Contents
- [Conventions used below](#conventions-used-below)
- [1. Database family](#1-database-family)
  - [1.1 Unified tDB* components and the Database dropdown](#11-unified-tdb-components-and-the-database-dropdown)
  - [1.2 Component catalog](#12-component-catalog)
  - [1.3 Connection settings (shared by all tDB*)](#13-connection-settings-shared-by-all-tdb)
  - [1.4 tDBInput settings](#14-tdbinput-settings)
  - [1.5 tDBOutput settings](#15-tdboutput-settings)
  - [1.6 tDBRow / tDBSP / tParseRecordSet](#16-tdbrow--tdbsp--tparserecordset)
  - [1.7 Transactions: tDBConnection / tDBCommit / tDBRollback / tDBClose](#17-transactions-tdbconnection--tdbcommit--tdbrollback--tdbclose)
  - [1.8 Bulk loading](#18-bulk-loading)
  - [1.9 SCD components](#19-scd-components)
  - [1.10 CDC components](#110-cdc-components)
  - [1.11 ELT components (summary)](#111-elt-components-summary)
- [2. File family](#2-file-family)
  - [2.1 Delimited / positional / regex / raw](#21-delimited--positional--regex--raw)
  - [2.2 XML and JSON](#22-xml-and-json)
  - [2.3 Excel, properties, LDIF, ARFF, EBCDIC, Avro, Parquet](#23-excel-properties-ldif-arff-ebcdic-avro-parquet)
  - [2.4 File management](#24-file-management)
  - [2.5 Schema metadata for files: date patterns, decimal separators](#25-schema-metadata-for-files-date-patterns-decimal-separators)
- [3. Processing family (non-map)](#3-processing-family-non-map)
- [4. Data types in a component schema](#4-data-types-in-a-component-schema)
- [5. Schema propagation rules and Dynamic schema](#5-schema-propagation-rules-and-dynamic-schema)
- [6. Database-specific notes](#6-database-specific-notes)
- [Gotchas](#gotchas)
- [Sources](#sources)

## Conventions used below
- Settings labels are given as they appear in the Component view (Basic settings /
  Advanced settings tabs). Studio 8.0 (monthly R20xx-xx releases) is the baseline; 7.3 differences noted.
- globalMap variables are read as `((Integer)globalMap.get("tDBOutput_1_NB_LINE"))`. Type:
  NB_* are Integer, ERROR_MESSAGE / QUERY / CURRENT_FILE* are String. Variables are
  "After" variables (set after the component finishes its subjob) unless noted "Flow" (set per row).
- The Outline view (bottom-left of Studio) lists every component's exposed variables; Ctrl+Space in
  any expression field autocompletes them.
- "Reject" row = a second output link available on many input/output components; it carries the
  input schema plus two String columns `errorCode` and `errorMessage` (added automatically, must be
  kept at the end of the reject schema).

## 1. Database family

### 1.1 Unified tDB* components and the Database dropdown
Since Studio 7.x the Palette shows generic `tDBConnection`, `tDBInput`, `tDBOutput`, `tDBRow`, ...
under Databases > DB Specifics is replaced by a `Database` dropdown in Basic settings (for a new
component a dialog "Select the database type" opens first). Choosing a value swaps the component for
the legacy specific component underneath: the generated Java and the `.item` XML reference the
specific component name (e.g. `tMysqlInput`), and the component label in the Designer becomes
`tDBInput_1` but the Component view shows the specific component's settings. Legacy components can
still be placed via the Palette search and are 1:1 the same thing.

| `Database` dropdown value | Legacy component prefix | Notes |
|---|---|---|
| MySQL | tMysql* | DB Version: MySQL 5 / MySQL 8 / MariaDB 10 (8.0 R2020+); connector-j jar per version |
| Amazon Aurora | tAmazonAurora* | MySQL-compatible; DB Version Aurora MySQL 5.6/5.7/8 (unverified exact list) |
| Oracle | tOracle* | Connection type: Oracle SID / Oracle Service Name / Oracle OCI / Oracle Custom / Oracle RAC / WALLET; DB Version 11/12/18/19/21 |
| PostgreSQL | tPostgresql* | also PostgresPlus (tPostgresPlus*) for EDB |
| Microsoft SQL Server | tMSSql* | JDBC Provider: Open source JTDS / Microsoft; also Azure SQL |
| Azure Synapse | tAzureSynapse* | 8.0; bulk via tAzureSynapseBulkExec |
| Amazon Redshift | tRedshift* | plus tRedshiftBulkExec / tRedshiftUnload / tRedshiftOutputBulk |
| Snowflake | tSnowflake* | Account/Region/Warehouse/Schema/Role; tSnowflakeOutput has Table Action/Output Action |
| DB2 | tDB2* | db2jcc4 jar; Schema mandatory |
| Teradata | tTeradata* | plus TPT/FastLoad/MultiLoad/TPump/FastExport exec components |
| Vertica | tVertica* | Vertica 9/10/11/12; COPY via tVerticaBulkExec |
| Greenplum | tGreenplum* | gpload via tGreenplumGPLoad |
| Netezza | tNetezza* | nzjdbc jar; tNetezzaBulkExec uses external table |
| Exasol | tExasol* | 7.0+ (unverified first version) |
| SAP HANA | tSAPHana* | ngdbc jar |
| Sybase | tSybase* | ASE / IQ (jconn4); tSybaseIQ* for IQ-specific bulk |
| Informix | tInformix* | ifxjdbc jar; Server name required |
| AS400 | tAS400* | jt400 jar |
| SQLite | tSQLite* | file DB, Database = path |
| HSQLDb | tHSQLDb* | Running Mode: HSQLDb Server / WebServer / In Process Persistent / In Memory |
| Access | tAccess* | UCanAccess driver (8.0), Jet/ODBC earlier |
| Firebird | tFirebird* | Jaybird driver |
| Ingres / VectorWise | tIngres*, tVectorWise* | Actian Vector/Avalanche reached via JDBC generic or tVectorWise* (unverified current naming) |
| MaxDB | tMaxDB* | |
| Derby (JavaDB) | tJavaDB* | |
| SingleStore (MemSQL) | tSingleStore* | 7.3+ |
| JDBC | tJDBC* | generic: JDBC URL + Drivers table + Driver Class + Mapping |
| Hive, Impala, BigQuery, Databricks, Delta Lake | tHive*, tImpala*, tBigQuery*, tDeltaLake* | big-data-spark.md / connectors-catalog.md |

Not every component exists for every DB: e.g. tDBSCD exists for MySQL, Oracle, PostgreSQL, MSSQL, DB2,
Teradata, Sybase, Informix, Netezza, Greenplum, Vertica (unverified full list); tDBCDC only for
MySQL, Oracle, PostgreSQL, MSSQL, DB2, AS400, Sybase, Informix, Teradata, Ingres (unverified full list).
`tDBFetch` does not exist as a Standard component (there is no tDBFetch; the row-fetching variants are tDBInput and tDBRow with Propagate QUERY's recordset).

### 1.2 Component catalog

| Component | Purpose | Key settings | globalMap (After unless noted) | Notes |
|---|---|---|---|---|
| tDBConnection | Open a connection reused by downstream components | all connection fields (1.3), Auto Commit, Use or register a shared DB Connection | ERROR_MESSAGE | Place at start of subjob; connect with OnSubjobOk. Does not auto-close: use tDBClose or TAC/JobServer will leak connections |
| tDBInput | SELECT, emit rows on Main | Query, Guess Query, Guess schema, Use cursor / Fetch size, Trim all String/Char columns, Enable Mapping File for Dynamic | NB_LINE, QUERY, ERROR_MESSAGE | Schema columns must match query column order, not names |
| tDBOutput | INSERT/UPDATE/DELETE from Main | Table, Action on table, Action on data, Die on error, Use batch mode/Batch Size, Commit every, Additional Columns, Use field options | NB_LINE, NB_LINE_INSERTED, NB_LINE_UPDATED, NB_LINE_DELETED, NB_LINE_REJECTED, QUERY, ERROR_MESSAGE | Reject link with errorCode/errorMessage only when Die on error is off and batch mode is off |
| tDBRow | Execute arbitrary SQL (DDL/DML/call) per subjob or per incoming row | Query, Die on error, Propagate QUERY's recordset, Use PreparedStatement, Commit every | QUERY, ERROR_MESSAGE, NB_LINE (some DBs, unverified) | No NB_LINE_INSERTED etc.; count via tDBOutput or a SELECT ROW_COUNT() |
| tDBCommit | COMMIT on an existing connection | Component List, Close Connection (checked by default) | ERROR_MESSAGE | Uncheck Close Connection if more subjobs follow |
| tDBRollback | ROLLBACK on connection | Component List, Close Connection | ERROR_MESSAGE | Attach via OnComponentError / OnSubjobError |
| tDBClose | Close connection | Component List | ERROR_MESSAGE | Always run at job end (OnSubjobOk from last subjob) |
| tDBSP | Call stored procedure | SP Name, Is Function / Return result in, Parameters table (Schema column -> Type IN/OUT/IN OUT/RECORDSET) | ERROR_MESSAGE, NB_LINE (unverified) | RECORDSET parameter type (Oracle REF CURSOR, MSSQL result set) requires an Object column + tParseRecordSet |
| tDBBulkExec | Server-side bulk load of an existing file into table | Table, Action on table, File Name, Field/Row separator, encoding, DB-specific options (1.8) | NB_LINE (not for every DB), ERROR_MESSAGE | File must be reachable by the DB server (or client-side for MySQL LOCAL) |
| tDBOutputBulk | Write Main flow to a flat file formatted for the bulk loader | File Name, Append, Field separator, Include header, Row separator, Create directory | NB_LINE, ERROR_MESSAGE | Pair with tDBBulkExec via OnSubjobOk |
| tDBOutputBulkExec | tDBOutputBulk + tDBBulkExec in one | union of both | NB_LINE, ERROR_MESSAGE | Convenience; no reject flow |
| tDBSCD | Slowly Changing Dimension load (Type 0/1/2/3) | SCD Editor (Source keys, Surrogate key, Type 0/1/2/3 fields, start/end date, version, active), Use batch mode (unverified per DB) | NB_LINE, NB_LINE_INSERTED, NB_LINE_UPDATED, NB_LINE_REJECTED (unverified), ERROR_MESSAGE | Dimension table must already exist (Action on table: None / Create / ...) |
| tDBSCDELT | SCD executed as SQL on the DB (source and target tables in same DB) | Source table, Target table, SCD Editor, Use batch (unverified) | NB_LINE_INSERTED, NB_LINE_UPDATED, ERROR_MESSAGE | Only Type 1/2 (Type 3 unsupported in SCDELT, unverified) |
| tDBCDC | Read captured changes for a subscriber from CDC tables | Schema using CDC, Table using CDC, Subscriber, Events to catch (Insert/Update/Delete), Keep data in CDC table | NB_LINE, ERROR_MESSAGE | Subscription set up via Repository > Metadata > Db Connections > CDC Foundation |
| tDBCDCOutput | Publish changes into a CDC table (for DBs without trigger support, e.g. Teradata) | CDC Table, Source Table, Action on data | NB_LINE | Rare; mainly Teradata/AS400 (unverified) |
| tDBColumnList | Iterate over the columns of a table | Table Name | COLUMN_NAME (Flow), NB_COLUMN (unverified) | Use with Iterate link; access `globalMap.get("tDBColumnList_1_COLUMN_NAME")` |
| tDBTableList | Iterate over tables of a schema | Where clause, table type filter | CURRENT_TABLE (Flow), NB_TABLE | pairs with tDBColumnList for metadata-driven jobs |
| tDBLastInsertId | Return auto-increment id of last INSERT on a connection | Component List | LAST_INSERT_ID (unverified name) | Adds column `last_insert_id` (Long) to flow; MySQL `LAST_INSERT_ID()`, MSSQL `@@IDENTITY`/`SCOPE_IDENTITY` |
| tDBInvalidRows / tDBValidRows | Split rows by DQ validation rule / SQL pattern | Validation rule or Custom pattern | NB_LINE | DQ licence; see data-quality-governance.md |
| tCreateTable | Generate CREATE TABLE from schema | Database Type, Table Name, Action on table | ERROR_MESSAGE | Separate component in Databases family, maps Talend types via mapping file |
| tParseRecordSet | Explode an Object column holding a java.sql.ResultSet into rows | Prev. Comp. Column list, Attribute table (schema col -> result set column name) | NB_LINE | Required after tDBRow Propagate QUERY's recordset or tDBSP RECORDSET |

### 1.3 Connection settings (shared by all tDB*)
| Setting | Values / behaviour |
|---|---|
| Database | dropdown (1.1); the resulting specific component name is what the .item stores |
| Property Type | Built-In (type values here) or Repository (pick a Metadata > Db Connections item; fields become read-only and are generated as `context.xxx` if the metadata was exported to a context group) |
| Use an existing connection | checkbox + Component List of tDBConnection_N in the job (incl. parent job via shared connection). Hides host/port/login fields |
| DB Version | per database (e.g. MySQL 5 / MySQL 8, Oracle 12-21, Postgres V9.x-V15, MSSQL 2016-2022); drives which driver module is loaded |
| Host / Port / Database / Schema | String expressions (`"localhost"`, `context.db_port`); Schema mandatory on Oracle/DB2/Postgres/MSSQL for Guess Query to work |
| Username / Password | Password field encrypted in .item; use `context.db_pwd` typed Password |
| Additional JDBC Parameters | appended to URL: `"noDatetimeStringSync=true&useSSL=false&allowLoadLocalInfile=true"` (MySQL), `"ssl=true&sslmode=require"` (Postgres), `"encrypt=true;trustServerCertificate=true"` (MSSQL Microsoft driver uses `;`) |
| Mapping | Advanced: which type-mapping file to use (`mapping_mysql.xml` ...), see section 4 |
| Auto Commit | tDBConnection only: commit after each statement; with it off you must add tDBCommit |
| Use or register a shared DB Connection | tDBConnection: `Shared DB Connection Name` string; child jobs (tRunJob) pick it up with the same name. Incompatible with tRunJob "Use an independent process" and "Use dynamic job" |
| Specify a data source alias | tDBConnection in Talend Runtime/ESB only: JNDI alias; unavailable when shared connection is checked |
| Use Transactions / tDBConnection in ESB | (unverified label) |
| Enable debug mode | Advanced (Output/Row): prints every executed SQL statement to the console |
| Use PreparedStatement | tDBRow/tDBInput Advanced: `?` placeholders + Set PreparedStatement Parameters table (Parameter Index, Parameter Type, Parameter Value) |
| Encoding | Advanced on some DBs (Oracle/Postgres input): charset for string decoding |
| tStatCatcher Statistics | Advanced on every component: feed tStatCatcher |

### 1.4 tDBInput settings
| Setting | Behaviour |
|---|---|
| Schema (Built-In / Repository) + Edit schema | Column order must match the SELECT list order; names are irrelevant to JDBC fetch (`rs.getXXX(index)`). Use `Sync columns` only on downstream components |
| Table Name | used by Guess Query / Guess schema only; the Query is what runs |
| Query Type | Built-In / Repository (SQL from Metadata > Db Connections > Queries) |
| Guess Query | builds `SELECT <cols> FROM <table>` with DB-specific quoting (`` `col` `` MySQL, `"col"` Postgres/Oracle, `[col]` MSSQL) |
| Guess schema | runs the query, infers Talend types via the mapping file; review BigDecimal vs Long results |
| Query | Java String expression: `"SELECT id, name FROM customers WHERE created > '" + context.since + "'"`; multi-line editor via `...` button; use `\"` for embedded double quotes |
| Use cursor / Fetch size (Postgres, Oracle "Use cursor", MySQL "Enable stream") | sets `Statement.setFetchSize(n)` so rows stream instead of loading the whole result set; Postgres cursor only works with Auto Commit off (needs transaction) |
| Trim all the String/Char columns / Trim column table | per-column trim of leading/trailing whitespace (CHAR padding) |
| Enable Mapping File for Dynamic | Advanced: how Dynamic column types are inferred |
| Allow special name for schema column names (unverified label) | keep reserved words/spaces in column names |
| Die on error | default checked; unchecked = error logged, subjob continues to next component |
| Convert Timestamp to Date / Use Oracle date as timestamp | Oracle-specific (see section 6) |
| Advanced > Use the Repository query / Use Jdbc escape (unverified) | |

Lookup mode: when tDBInput feeds a tMap lookup input with "Reload at each row", the query may reference
`globalMap` keys set in the tMap lookup expression (see tmap-expressions.md).

### 1.5 tDBOutput settings
| Setting | Values / behaviour |
|---|---|
| Table | String expression; `context.schema + ".target"` works only if Schema field left empty (DB-dependent quoting) |
| Action on table | None / Drop and create table / Create table / Create table if does not exist / Drop table if exists and create / Clear table (DELETE) / Truncate table. Create uses the mapping file to derive DDL; Length/Precision from schema |
| Action on data | Insert / Update / Insert or update / Update or insert / Delete / Replace (MySQL `REPLACE INTO`) / Insert if not exist (MySQL `INSERT IGNORE`-like, unverified exact DBs) / Insert ignore (MySQL) / Upsert-merge on Oracle (`Insert or update` is implemented as INSERT then UPDATE on duplicate-key error, NOT MERGE, except Snowflake/Teradata which generate MERGE) |
| Schema | keys (checkbox `Key` in Edit schema) are what Update/Delete use for the WHERE clause unless Use field options overrides |
| Die on error | checked: first SQL error kills the job (exit code 1). Unchecked: failing row goes to Reject link, job continues, NB_LINE_REJECTED increments |
| Use batch mode / Batch Size (Advanced) | `addBatch()/executeBatch()` every N rows (default 10000 for MySQL, 100 for others, unverified). Only for Insert / Update / Delete actions. Disables per-row Reject rows (whole batch fails; only ERROR_MESSAGE) |
| Commit every | number of rows per `commit()` (default 10000). Only shown when Use an existing connection is off; with an existing connection the tDBConnection's Auto Commit / tDBCommit decides. Set Commit every >= Batch size and a multiple of it |
| Additional Columns | table: Name / SQL expression (e.g. `"NOW()"`, `"UPPER(?)"`, `"nextval('seq')"`) / Position (Before / After / Replace) / Reference column. Not available with Use batch mode on most DBs, nor with bulk actions |
| Use field options | table per schema column: Update Key / Deletion Key / Updatable / Insertable (and `Use Update Statement`/`Use Insert`? no: columns are Key for update, Key for delete, Updatable, Insertable). Lets you update on a non-PK column or exclude an auto-increment column from INSERT |
| Enable debug mode | print generated SQL per row |
| Support null in "SQL WHERE" statement | generates `col IS NULL` instead of `col = NULL` for key columns that are null in Update/Delete |
| Use Hint Options (Oracle) | `/*+ APPEND */` etc. |
| Convert columns and table to uppercase (Oracle/Snowflake, unverified label) | |
| Use Column Case Sensitive / Use schema keys for "Where" (unverified) | |
| Extend Insert (MySQL) | `INSERT ... VALUES (...),(...)` multi-row statement; `Number of rows per insert`; cannot be combined with Use batch mode or with Reject |
| Use duplicate key update (MySQL) | `ON DUPLICATE KEY UPDATE` with Column / Value table |
| Use existing dynamic schema (unverified exact label: "Use dynamic schema") | with a Dynamic column the component builds INSERT/CREATE TABLE at runtime from the Dynamic metadata |
| Use update statement without subqueries (MSSQL) / Identity insert (MSSQL `SET IDENTITY_INSERT ON`) | DB-specific |

Reject link: available only when Die on error is unchecked and (Use batch mode off or, on
some DBs, batch on but with per-batch rejects unsupported). Columns = input schema + `errorCode`
(String, vendor SQLState/error code) + `errorMessage` (String). Typical pattern: tDBOutput --reject--> tFileOutputDelimited.

### 1.6 tDBRow / tDBSP / tParseRecordSet
- tDBRow runs `Query` once per incoming row when connected via Main, once when started by a trigger.
  Each row can embed input values: `"UPDATE t SET x='" + row1.x + "' WHERE id=" + row1.id`, or safer with
  Use PreparedStatement (`"UPDATE t SET x=? WHERE id=?"` + parameters `row1.x` / `row1.id`; Parameter Type
  from the Talend type list: Int, String, Date, BigDecimal, Boolean, ...).
- Multiple statements in one Query: MySQL needs `allowMultiQueries=true` in Additional JDBC
  Parameters; Oracle needs an anonymous `BEGIN ... END;` block; Postgres accepts `;`-separated statements.
- `Propagate QUERY's recordset`: Advanced checkbox + `use column` (an Object-typed column of the
  output schema). The ResultSet is placed in that column; follow with tParseRecordSet (Prev. Comp.
  Column list = that column; Attribute table maps schema columns to result-set column names).
  tDBRow output schema may differ from input in this mode.
- tDBRow `Commit every` only shows without an existing connection; with Auto Commit off and no
  tDBCommit, DDL commits implicitly on most DBs but DML is lost.
- tDBSP: `SP Name`, `Is Function / Return result in` (pick the schema column receiving the return
  value), Parameters table: Schema Column, Type = IN / OUT / IN OUT / RECORDSET. Output columns for
  OUT params must exist in the schema. Oracle REF CURSOR -> RECORDSET into an Object column ->
  tParseRecordSet. MSSQL SPs returning result sets: use tDBInput with `"EXEC dbo.proc @p=1"` instead
  (simpler) or RECORDSET.
- tDBRow globalMap: QUERY (the last executed SQL text) and ERROR_MESSAGE. No reliable NB_LINE for
  affected rows; use `SELECT ROW_COUNT()` (MySQL) / `@@ROWCOUNT` (MSSQL) / `GET DIAGNOSTICS` in a follow-up
  tDBInput, or Propagate QUERY's recordset with `UPDATE ... RETURNING`.

### 1.7 Transactions: tDBConnection / tDBCommit / tDBRollback / tDBClose
```
tDBConnection_1 (Auto Commit off)
  --OnSubjobOk--> tFileInputDelimited_1 --Main--> tDBOutput_1 (Use an existing connection: tDBConnection_1)
                     --OnSubjobOk--> tDBCommit_1 (Component List: tDBConnection_1, Close Connection: checked)
                     --OnSubjobError--> tDBRollback_1 (Close Connection: checked)
```
- Without `Use an existing connection`, every tDB* component opens its own connection and commits
  per `Commit every`; there is no cross-component transaction.
- With an existing connection and Auto Commit off, nothing is committed until tDBCommit; a job
  that dies before tDBCommit loses everything (desired for all-or-nothing loads).
- tDBCommit/tDBRollback/tDBClose `Close Connection` default checked; a later subjob using the same
  connection then fails with "Connection is closed" / "No operations allowed after connection closed".
- Shared connection: tDBConnection `Use or register a shared DB Connection` + name; in the child job
  put a tDBConnection with the same name and the same checkbox (child-side fields otherwise ignored).
- MySQL `autoReconnect=true` and MSSQL `loginTimeout` go in Additional JDBC Parameters; long jobs with
  a single connection open at start may hit `wait_timeout` (MySQL) before the first write.

### 1.8 Bulk loading
| DB | Components | Mechanism | Key settings |
|---|---|---|---|
| MySQL | tMysqlOutputBulk, tMysqlBulkExec, tMysqlOutputBulkExec | `LOAD DATA [LOCAL] INFILE` | Local filename (Load data local infile needs `allowLoadLocalInfile=true` in JDBC params and `local_infile=1` server-side); Action on data: Insert / Update / Replace / Ignore; Field terminated by / Enclosed by / Lines terminated by; Set columns names; Records contain NULL value |
| PostgreSQL | tPostgresqlOutputBulk, tPostgresqlBulkExec, tPostgresqlOutputBulkExec | `COPY table FROM 'file'` (server path) or `COPY ... FROM STDIN` via CopyManager when `Use COPY FROM STDIN`? (unverified: Studio uses server-side COPY by default, the file must be on the DB host or shared) | Copy mode: Table / Query? (unverified), Row separator, Field separator, Null string, File type CSV/Text, Enclosure |
| Oracle | tOracleOutputBulk, tOracleBulkExec, tOracleOutputBulkExec | SQL*Loader (`sqlldr`) invoked locally; Studio writes a `.ctl` control file | Action on data: Insert / Append / Replace / Truncate; `Use existing control file`, Control file path, Field separator, Specify .ctl file's INTO TABLE clause manually, Record format (Fixed/Delimited), Direct Path; requires Oracle client with sqlldr in PATH; NLS_LANG affects encoding |
| MSSQL | tMSSqlOutputBulk, tMSSqlBulkExec, tMSSqlOutputBulkExec | `BULK INSERT` (file must be visible to the SQL Server service) or `bcp` utility (`Use bcp`? unverified label) | Action on table, Action on data Insert/Bulk insert, Field terminator, Row terminator, First row, Code page, Keep identity, Check constraints, Fire triggers, Batch size |
| Snowflake | tSnowflakeOutputBulk, tSnowflakeBulkExec, tSnowflakeOutputBulkExec | file -> stage (`PUT` to internal stage, or external S3/Azure stage) -> `COPY INTO` | Storage: Internal / S3 / Azure / GCS; Stage folder; Table Action; Output Action Insert/Update/Upsert/Delete (merge after copy via temp table); Compress by gzip; Use custom Snowflake field delimiter/Line separator; Purge after load; Copy command options (`ON_ERROR`, `FORCE`, `PURGE`) |
| Redshift | tRedshiftOutputBulk, tRedshiftBulkExec, tRedshiftOutputBulkExec, tRedshiftUnload | `COPY table FROM 's3://...'` with IAM role or access key/secret; `UNLOAD` to S3 | S3 bucket/key, Access Key/Secret Key or `Use IAM role` (Role ARN), Data file type Delimited/CSV/JSON/AVRO/Fixed width, Compressed (gzip/lzop/bzip2), Encrypt, Date format/Time format, Fill missing fields, Accept any date, Ignore blank lines, Load region, Truncate columns, Remove quotes, Round decimal; UNLOAD: Parallel, Allow overwrite, Add quotes, Escape, Delimiter, Max file size |
| Teradata | tTeradataFastLoad, tTeradataMultiLoad, tTeradataTPump, tTeradataTPTExec, tTeradataTPTUtility, tTeradataFastExport | invoke Teradata utilities installed locally (`fastload`, `mload`, `tpump`, `tbuild`, `fexp`) with generated scripts | Execution file path, Script generated/`Use existing script`, Load file, Error table, Log table, Work table, Checkpoint, Sessions, Max errors (TPT) |
| Vertica | tVerticaOutputBulk, tVerticaBulkExec, tVerticaOutputBulkExec | `COPY ... FROM LOCAL` / `FROM STDIN` | Exception file, Rejected data file, Direct/Auto/Trickle load method, Enforce length, Abort on error, Skip rows |
| Greenplum | tGreenplumGPLoad, tGreenplumOutputBulk, tGreenplumBulkExec | `gpload` utility (YAML control file generated) or `COPY` | gpload path, Port range, Error table, Local hostname, Insert/Update/Merge, Match columns, Update columns, Encoding, Log errors |
| Netezza | tNetezzaBulkExec, tNetezzaNzLoad, tNetezzaOutputBulk | External table `CREATE EXTERNAL TABLE ... USING (...)` then INSERT SELECT, or `nzload` | Delimiter, Escape char, Date style/Date delim, Max errors, Ctrl chars, Null value, Fill record, Log/Bad dir |
| DB2 | tDB2BulkExec (LOAD/IMPORT via `db2` CLP? unverified), tDB2OutputBulk | `LOAD FROM ... OF DEL` | DB2 client required locally |
| Sybase IQ | tSybaseIQOutputBulkExec, tSybaseIQBulkExec | `LOAD TABLE` | |
| Informix | tInformixOutputBulkExec, tInformixBulkExec | `dbload` / `LOAD FROM` (unverified) | |
| Azure Synapse | tAzureSynapseBulkExec | file in Azure Blob/ADLS -> `COPY INTO` / PolyBase external table | Storage account, Container, Credential (Account key / SAS / Managed identity), File format, Identity insert (unverified list) |
| SQLite | tSQLiteOutput only (no bulk) | | |

Common pattern: `tFileInputDelimited --> tDBOutputBulk` (writes temp file) `--OnSubjobOk--> tDBBulkExec`.
Bulk components expose NB_LINE (rows written to file for OutputBulk; rows loaded for BulkExec on
DBs that report it) and ERROR_MESSAGE; no Reject link (rejected rows go to the loader's bad/error
files or error tables).

### 1.9 SCD components
tDBSCD (row-by-row from Studio) and tDBSCDELT (SQL executed inside the DB; source table must already
be in the same DB) share the **SCD Editor** (button in Basic settings). The dimension table must
exist or be created via `Action on table` (None / Create / Create if not exists / Drop and create ...).

| SCD Editor area | Settings | Notes |
|---|---|---|
| Unused | all input columns start here; drag into the other panes | |
| Source keys | one or more input columns that identify the business entity | natural key; drives lookup of the current dimension row |
| Surrogate keys | `name` of the dimension PK column + `creation`: Auto increment (DB identity) / Input field (take a column) / Routine (e.g. `Numeric.sequence("s1",1,1)`) / Table max + 1 / DB sequence (Oracle/Postgres/DB2: `sequence name`) | `complement` column: optional second technical key (unverified) |
| Type 0 fields | columns copied at insert and never updated afterwards | |
| Type 1 fields | overwrite in place (no history) | |
| Type 2 fields | change -> close current row and insert a new version. Versioning options: `start date` (column; creation = input field or job start / execution date), `end date` (column; null or a fixed date `9999-12-31` for current row, label "Set end date to" unverified), `version` (Integer column, increments), `active` (Boolean/String flag `true`/`1`) | Start/end are Date columns in the dimension schema; `L1/L2/L3` labels in older docs correspond to the three optional type-2 attributes start/end + version + active |
| Type 3 fields | keep current value and one previous value: `current value` column + `previous value` column | |

- Output schema of tDBSCD = dimension table schema (incl. surrogate key and SCD technical columns); use
  `Sync columns`? No: the schema is defined by the SCD editor; edit the schema before opening the editor.
- Reject link (unverified availability per DB) carries input rows whose source key is null.
- SCDELT additional settings: `Source table`, `Target table` (unverified exact labels), the SQL is a
  sequence of INSERT ... SELECT / UPDATE statements; Type 3 is not supported by SCDELT (unverified).
- Dates: start date default = execution start; for backdated loads use Input field.
- Performance: tDBSCD issues a SELECT per input row to find the current record; sort and
  deduplicate input first (tUniqRow on source key) because two rows with the same key in one run
  produce two type-2 versions with identical start dates.

### 1.10 CDC components
Change Data Capture (Enterprise feature) is configured in the Repository, not in the component:
Metadata > Db Connections > right-click connection > CDC > `Create CDC`, pick the **CDC
Foundation** connection (a schema where `TCDC_*` tables are created), then on each table
`Add CDC` -> `Create Subscriber and Execute SQL Script` dialog: Subscriber name, `Events to catch`
(Insert / Update / Delete), the generated SQL (triggers + change table) is executed. Source tables
need a primary key. Captured changes live in `TCDC_<table>` tables (one row per change with
`TALEND_CDC_SUBSCRIBERS_NAME`, `TALEND_CDC_STATE`, `TALEND_CDC_TYPE` (I/U/D), `TALEND_CDC_CREATION_DATE`
plus the PK columns) and a view per subscriber; subscribers are registered in `TSUBSCRIBERS`
(unverified exact names).

| Mode | DB | Notes |
|---|---|---|
| Trigger mode | MySQL, Oracle, PostgreSQL, MSSQL, DB2, Sybase, Informix, Ingres, Teradata (via tDBCDCOutput, no triggers), AS400 (journal) | default; triggers on source table write PK + operation into TCDC_ table |
| Redo/Archive log mode | Oracle only | reads Oracle redo/archive logs via LogMiner-based mechanism; needs `ARCHIVELOG`, supplemental logging; subscriber tables still used |
| XStream mode | Oracle 11.2+ only | uses Oracle XStream Out (GoldenGate licence); captures full row images |

tDBCDC Basic settings: Database, connection (usually Repository CDC connection), `Schema using CDC`,
`Table using CDC`, `Subscriber` (String), `Events to catch` Insert / Update / Delete checkboxes,
`Keep data in CDC table` (do not mark changes consumed; default off => rows are consumed/removed for
this subscriber), `Limit` (unverified). Output schema = source table columns (from the CDC view).
globalMap: NB_LINE, ERROR_MESSAGE. Trigger mode captures only the PK and operation type: the
component re-reads current values from the source table by joining on the PK, so a row deleted
after being updated appears once with type D and old values unavailable. See patterns-gotchas.md
for CDC design patterns.

### 1.11 ELT components (summary)
Per DB there is a trio tELT<Db>Input / tELT<Db>Map / tELT<Db>Output (generic `tELTInput`,
`tELTMap`, `tELTOutput` with a Database dropdown in 8.0). They generate one `INSERT INTO ... SELECT
... JOIN ...` executed on the DB, no data flows through the Job.
- tELTInput: `Default Table Name` (the table), `Default Schema Name`, schema = table columns
  (Repository metadata recommended). No `Query`. Connects to tELTMap with a link named after the
  table (the link name IS the table alias used in SQL; rename the link to match `Different table
  name` / alias).
- tELTOutput: `Action on data` Insert / Update / Delete / Merge (DB-dependent), `Default Table
  Name`, `Use different table name` + `Table name`, `Use different table alias`? (alias is set on
  the tELTMap output table), `Action on table` (Create/Drop...), `Use WHERE conditions table`.
- tELTMap: `Use an existing connection`, `Style` of join (INNER/LEFT OUTER/...) per table, `Add
  alias` (table alias), `Generated SQL Select query` tab shows the SQL. Expression details in
  tmap-expressions.md.
- globalMap: tELTOutput NB_LINE, NB_LINE_INSERTED, ERROR_MESSAGE (docs list no UPDATED/DELETED).

## 2. File family

### 2.1 Delimited / positional / regex / raw
| Component | Purpose | Key Basic settings | Key Advanced settings | globalMap | Notes |
|---|---|---|---|---|---|
| tFileInputDelimited | read CSV/TSV | File name/Stream (String path or `(java.io.InputStream)globalMap.get(...)`), Row Separator (`"\n"`), Field Separator (`";"`), `CSV options` (enables Escape char `"\\"`/`"\""` and Text enclosure `"\""`), Header (rows to skip, 1 = header line), Footer, Limit, Skip empty rows, Uncompress as zip file, Die on error | Advanced separator (for numbers): Thousands separator / Decimal separator; Extract lines at random (+ Number of lines); Trim all columns / Check column to trim; Check each row structure against schema; Check date; Split row before field; Permit hexadecimal (0xNNN) or octal (0NNN) for numeric types; Encoding (ISO-8859-15 / UTF-8 / Custom); Enable parallel execution (unverified) | NB_LINE, ERROR_MESSAGE | Reject link (Die on error off): row + errorCode + errorMessage; type-conversion errors (bad date/number) go to reject, structural errors need Check each row structure. CSV options required for quoted fields containing separators or newlines; without it field separator may be a regex-like multi-char string, with it a single char |
| tFileOutputDelimited | write CSV | File Name, Row Separator, Field Separator, Append, Include Header, Compress as zip file, CSV options (Escape char, Text enclosure), Encoding? (Advanced) | Advanced separator (for numbers); CSV options; Create directory if not exists (default on); Split output in several files + Rows in each output file; Custom the flush buffer size + Row number; Output in row mode (write line by line, needed for mixed Append writers); Encoding; Don't generate empty file; Throw an error if the file already exist; Use byte length as the cardinality (positional-style padding counts bytes, unverified placement); Row Separator (Advanced on 7.x) | NB_LINE, FILE_NAME (unverified on older versions) | Header is written only when the file is created/overwritten, not on Append to existing file (Include header + Append on existing non-empty file skips header since 6.x); Split names files `name_1.csv`, `name_2.csv` |
| tFileInputPositional | fixed-width read | File name, Row separator, Pattern `"10,20,15,*"` (column widths, `*` = rest), Header/Footer/Limit, Skip empty rows, Die on error, Uncompress as zip | Customize (per-column: Column / Size / Alignment / Padding char), Advanced separator, Trim all columns, Check each row structure, Permit hexadecimal, Encoding | NB_LINE, ERROR_MESSAGE | Widths are in characters; multi-byte encodings may need byte-based option |
| tFileOutputPositional | fixed-width write | File Name, Row separator, Formats table (Column, Size, Padding char, Alignment Left/Right, Keep), Use byte length as the cardinality, Append, Include header | Create directory, Custom flush buffer, Encoding, Don't generate empty file, Throw error if exists | NB_LINE | Values longer than Size are truncated silently unless Keep is checked (unverified semantics of Keep) |
| tFileInputRegex | parse lines with a regex | File name, Row separator, Regex `"^(\\d+);(\\w+)$"` (one capture group per schema column), Header/Footer/Limit, Skip empty rows, Die on error | Encoding, Trim | NB_LINE | Non-matching lines dropped (or to reject? no reject link, unverified) |
| tFileInputFullRow | each line as one String column `line` | File name, Row separator, Header, Footer, Limit, Skip empty rows, Die on error | Encoding | NB_LINE | Feed tExtractDelimitedFields / tExtractRegexFields |
| tFileInputRaw | whole file into one column `content` (String) or byte[] | Filename, Read the file as a string / as bytes, Encoding | | NB_LINE (1) | pairs with tExtractJSONFields/tExtractXMLField on `content` |
| tFileOutputRaw | write one column value to a file | Filename, Mode: `Write a string`/`Write bytes`?, Append (unverified label), Create directory | | NB_LINE | |
| tFileInputMSDelimited | multi-schema delimited (record type column) | File name, Row/Field separator, Multi Schema Editor (record-type cardinality, parent/child schemas) | | NB_LINE | one output link per schema |
| tFileInputMSPositional | multi-schema positional | Multi Schema Editor with patterns per record type | | NB_LINE | |
| tFileOutputMSDelimited | multi-schema delimited write | Schemas table (one per input link), Use Multi Field Separators | | NB_LINE | |
| tFileInputFullRow + tExtract* | preferred way to handle weird files | | | | |
| tFileStreamInputDelimited etc. | Spark Streaming only; not in Standard Palette | | | | big-data-spark.md |

Multi-char field separators: without CSV options the separator string is used literally in a
`split`-like parse; `"\t"` tab, `"\u00A7"` unicode escapes allowed. Row separator `"\r\n"` vs `"\n"`:
reading with `"\n"` on CRLF files leaves `\r` on the last column unless Trim is on (Studio's reader
actually normalizes CRLF in most versions; keep `"\n"`).

### 2.2 XML and JSON
| Component | Purpose | Key settings | globalMap | Notes |
|---|---|---|---|---|
| tFileInputXML | read XML by XPath | File name/Stream, Loop XPath query (`"/root/order"`), Mapping table: Column / XPath query (relative to loop, `"@id"`, `"customer/name"`, `"."`) / Get Nodes (return the XML fragment as String instead of text value), Limit, Die on error; Advanced: Ignore DTD file, Advanced separator, Ignore the namespaces, Generation mode: Fast with low memory consumption (SAX) / Slow and memory-consuming (Dom4j) / Xerces (streaming with namespaces, 7.x+), Validate date, Encoding | NB_LINE, ERROR_MESSAGE | SAX mode: no namespaces, Get Nodes limited, XPath functions unsupported, `..` parent axis unsupported; use Dom4j for small files, Xerces for large namespaced files |
| tFileInputMSXML | multi-schema XML (several loop elements -> several outputs) | Root XPath query, Outputs table (Schema, XPath loop expression), Mapping per output | NB_LINE | Dom4j only |
| tExtractXMLField | parse XML held in a String/Document column of the flow | XML field (column), Loop XPath query, Mapping, Get Nodes, Ignore DTD, Generation mode | NB_LINE | typical after tFileInputRaw / tRESTClient / tDBInput CLOB |
| tFileOutputXML | write flat XML (one element per row) | File name, Row tag (`"row"`), Root tags (list), Output format: Advanced (Split output per N rows), Encoding, Create directory, Compress as zip, Trim data, Remove empty element, Include header, Use schema column name/Use custom label (Advanced > Output format: Use schema column name / Set the label as attribute?) | NB_LINE | For nested XML use tAdvancedFileOutputXML |
| tAdvancedFileOutputXML | nested XML via XML tree | File name, Configure XML tree editor (drag schema columns onto tree nodes; `Set As Loop Element` on repeating node; `Set As Group Element` on parent whose children are grouped by equal values; `As attribute`/`Set a namespace`/`Set a fixed value`; Create empty element if needed), Append the source xml file, Generate document (Document type output column on `Output` schema instead of file), Advanced: Split output in several files, Create directory, Encoding, Trim data, Remove empty element, Advanced separator, Row separator, Compress as zip, Don't generate empty file | NB_LINE | Group element requires input sorted by the grouping columns |
| tWriteXMLField | build XML into a Document/String column of the flow (same XML tree editor) | Output column, XML tree, Remove root element, Group by table | NB_LINE | combine with tFileOutputDelimited / tRESTClient |
| tFileInputJSON | read JSON file/URL | File name/URL/Stream, Read By: JsonPath (recommended) / Xpath / JsonPath without loop, Loop Json query (8.0 label; 7.3 "Loop Jsonpath query", e.g. `"$.orders[*]"`), Mapping: Column / Json query or XPath (`"id"`, `"customer.name"`, `"items[0].sku"`), Die on error; Advanced: Encoding, Use the loop node as root (unverified), Validate date, Advanced separator | NB_LINE, ERROR_MESSAGE | XPath mode converts JSON to XML internally: field names starting with digits or containing `-`/`@` break; JsonPath uses Jayway JsonPath (`$..`, filters `[?(@.x>1)]`) |
| tExtractJSONFields | same, from a String/Document column | JSON field, Read By, Loop Jsonpath query, Mapping (Column, Json query, Get Nodes? no), Die on error | NB_LINE | typical after tRESTClient / tHttpRequest / tDBInput JSON column |
| tFileOutputJSON | write flat JSON | Name of data block (`"data"`, empty for bare array), Generate an array json (array of objects without wrapper), File Name, Create directory, Encoding, Compress? | NB_LINE | nested JSON: tWriteJSONField (XML-tree editor, `Set As Loop Element`, `Set As Array`? no: the tree editor drives arrays via loop element) |
| tWriteJSONField | build JSON into a column | Output Column, Configure JSON Tree (same editor as tAdvancedFileOutputXML; `Set As Loop Element`, `As attribute` has no meaning), Group by, Remove root node, Keep root node, Serialize: Json array/object (unverified label), `Convert empty string/null to ...` (unverified) | NB_LINE | integers/booleans are emitted as strings unless the schema column type is numeric/boolean (8.0 emits typed since R2021-xx, unverified) |
| tXMLMap | map-based XML, tmap-expressions.md | | | |

XPath/JsonPath for attributes: `"@attr"`; current loop node text `"."`; namespaces: declare in the
Mapping with `"ns:node"` only in Dom4j/Xerces mode, or check Ignore the namespaces.

### 2.3 Excel, properties, LDIF, ARFF, EBCDIC, Avro, Parquet
| Component | Purpose | Key settings | globalMap | Notes |
|---|---|---|---|---|
| tFileInputExcel | read xls/xlsx | File name/Stream, Read excel2007 file format(xlsx) (needed for .xlsx/.xlsm; enables Excel 2007+ password), Generation mode (xlsx only): Memory-consuming (User mode, 7.x) / Less memory consumed for large excel (Event mode, streaming via XSSF event API), All sheets / Sheet list (Sheet name or index, `Use Regex`), Header, Footer, Limit, Affect each sheet (header/footer), Die on error, First column / Last column (1-based), Stop reading on encountering empty rows (xls only), Advanced: Advanced separator (for numbers), Trim all columns, Encoding, Convert date column to string? (unverified), Read real value for numbers, `Don't validate the cells` (unverified), Ignore warnings? | NB_LINE, CURRENT_SHEET (Flow) | Numeric cells read into String columns come as `1.0E7`/`123.0`: use `Read real value for numbers` or BigDecimal column + pattern; Date cells need Date column; xls = Apache POI HSSF (max 65536 rows), xlsx = XSSF; Event mode cannot read formulas' cached results in some versions |
| tFileOutputExcel | write xls/xlsx | File Name, Write excel2007 file format(xlsx), Sheet name, Include header, Append existing file / Append existing sheet, Is absolute Y pos / First cell X,Y, Keep existing cell format, Font, Define all columns auto size, Create directory, Password protection (xlsx), Use streaming mode (SXSSF, 7.3+ unverified label) | NB_LINE | Dates written as Excel dates when column is Date; `Keep existing cell format` + Append for templates |
| tFileInputProperties | read .properties / .ini | File Format: .properties / .ini (+ Section Name), File name, Encoding | NB_LINE | output schema fixed: `key`, `value` (String) |
| tFileOutputProperties | write .properties/.ini | File format, File name, Append? (unverified), Encoding | NB_LINE | input schema must be key/value |
| tFileInputLDIF | read LDIF | File name, Schema with LDAP attribute names, Value separator (for multi-valued attrs), Die on error | NB_LINE | base64 values decoded automatically |
| tFileOutputLDIF | write LDIF | File name, Change type: Add / Modify / Delete / Modrdn / Content (unverified set), Wrap (line wrap 78), Encoding, Append, Multi-values separator | NB_LINE | `dn` column required |
| tFileInputARFF / tFileOutputARFF | Weka ARFF | File name, Row separator, Header | NB_LINE | rarely used |
| tFileInputEBCDIC | mainframe EBCDIC with COBOL copybook | Copybook (file path or Repository Metadata > File EBCDIC), Data file, Record format (fixed/variable, RDW), Code page (`"cp037"`, `"cp1047"`, `"cp500"`), multi-schema outputs per copybook record | NB_LINE | There is no separate `tCopybook` component: the copybook is parsed by the File EBCDIC metadata wizard (Enterprise) |
| tFileInputAvro / tFileOutputAvro | Avro container files (Standard, 7.3+ in Standard palette; earlier Big Data only) | Folder/File, Compression (none/deflate/snappy), schema inferred by wizard | NB_LINE | Logical types (decimal, timestamp) map to BigDecimal/Date only in newer versions (unverified) |
| tFileInputParquet / tFileOutputParquet | Parquet files in Standard Jobs (8.0; local filesystem or S3/HDFS via tS3Configuration etc.) | Folder/File, Compression (uncompressed/gzip/snappy), `Merge result to single file` (output), Use Hadoop configuration? | NB_LINE | Pulls Hadoop client jars (large module download on first use); timestamp INT96 vs TIMESTAMP_MILLIS compatibility issues with Spark-written files |

### 2.4 File management
| Component | Purpose | Key settings | globalMap | Notes |
|---|---|---|---|---|
| tFileList | iterate files/dirs | Directory, FileList Type: Files / Directories / Both, Include subdirectories, Case Sensitive: Yes/No, Generate error if no file found, Use Glob Expressions as Filemask (default on; off = Java regex), Files (Filemask table: `"*.csv"`, `"data_??.txt"`), Order by: By default / By file name / By file size / By modified date, Order action: ASC / DESC; Advanced: Use Exclude Filemask, Format file path to slash(/) style | CURRENT_FILE (name with ext), CURRENT_FILEPATH (full path), CURRENT_FILEDIRECTORY, CURRENT_FILEEXTENSION, NB_FILE (After) | All CURRENT_* are Flow variables valid inside the Iterate; connect `tFileList --Iterate--> tFileInputDelimited` with File name `((String)globalMap.get("tFileList_1_CURRENT_FILEPATH"))`. Order action is a radio, cannot be context-driven |
| tFileExist | test existence | File name | EXISTS (Boolean, After), FILENAME | use `If` trigger: `((Boolean)globalMap.get("tFileExist_1_EXISTS"))` |
| tFileCopy | copy/move/rename | File Name, Destination directory, Rename (+ Destination filename), Remove source file (= move), Replace existing file, Create the directory if it doesn't exist, Copy a directory (+ Include subdirectories? unverified) | DESTINATION_FILEPATH, DESTINATION_FILE, SOURCE_FILEPATH? (unverified) | there is no tFileRename component: use tFileCopy + Rename, or tSystem `mv` |
| tFileDelete | delete file/dir | File Name, Delete directory (+ Fail on error?), Delete file | DELETE_PATH, CURRENT_STATUS (`"File deleted."`), ERROR_MESSAGE? | silent when file missing unless Fail on error (unverified) |
| tFileArchive | zip/gzip/tar | Directory (source), Archive file, Compress level (Best/Normal/Fast), Encrypt files (zip password), All files / Files filemask, Subdirectories, Format: ZIP / GZIP / TAR? (7.x adds GZIP/TAR), Overwrite existing | ARCHIVE_FILEPATH, ARCHIVE_FILE? | gzip of a single file; zip of directory |
| tFileUnarchive | extract | Archive file, Extraction Directory, Use the archive name as root directory, Need password, Extract files masks? | UNARCHIVE_PATH? (unverified) | supports zip, gz, tar, tgz |
| tFileCompare | byte compare two files | File to compare, Reference file, If differ output file, Print to console | DIFFERENCE (Boolean), MESSAGE | output schema fixed (differ flag) |
| tFileProperties | metadata of one file | File | emits one row: abs_path, dirname, basename, mode_string, size, mtime, mtime_string | NB_LINE | for timestamps/sizes |
| tFileRowCount | count lines | File Name, Row separator, Ignore empty rows, Encoding | COUNT (Integer) | cheap pre-check before processing |
| tFileTouch | create empty file / update mtime | File Name, Create directory if not exists | | |
| tCreateTemporaryFile | temp file | Remove file when execution is over, Use temporary system directory / Directory, Template (`"talend_XXXXXXX"`), Suffix | FILEPATH, FILE | |
| tChangeFileEncoding | re-encode | Input/Output file, Input encoding, Output encoding (ISO-8859-15/UTF-8/custom), Overwrite | | BOM is not stripped |
| tFileInputFullRow | see 2.1 | | | |

### 2.5 Schema metadata for files: date patterns, decimal separators
- In Edit schema, a `Date` column has a **Date Pattern** attribute (e.g. `"dd-MM-yyyy"`,
  `"yyyy-MM-dd HH:mm:ss"`, `"yyyy-MM-dd'T'HH:mm:ss.SSSXXX"`). Input components parse the String
  with `TalendDate.parseDate(pattern, value)` (lenient off by default on delimited inputs in recent
  versions; "Check date" enforces strict parsing); output components format with the same pattern.
  An empty pattern on a Date column in a file schema causes `Unparseable date` at runtime.
- Patterns use `java.text.SimpleDateFormat` syntax: `MM` month, `mm` minute, `yyyy` year, `HH` 24h,
  `hh` 12h, `SSS` millis, `XXX` ISO offset, `Z` RFC offset, `EEE`/`MMM` locale-dependent.
- Numeric columns: `Advanced separator (for numbers)` on delimited/positional/Excel components sets
  `Thousands separator` (default `","`) and `Decimal separator` (default `"."`) applied when
  converting String to numeric types; needed for `1.234,56` files. BigDecimal keeps scale as parsed.
- Length / Precision in a file schema are informational for files (used for DDL when the schema
  is propagated to tDBOutput Create table and for tFileOutputPositional sizes).
- Repository metadata (Metadata > File delimited wizard) stores the same attributes; a component
  with Property Type = Repository locks these fields and shows a "Repository" badge; `Guess` in the
  wizard infers types from sample rows (usually String + a few Integer) and must be corrected manually.
