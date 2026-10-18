# Connectors catalog: Cloud, SaaS, business apps, NoSQL, messaging, Internet, technical

> Verification: doc-derived (help.qlik.com / help.talend.com search snippets, Talend GitHub, Maven Central) plus model knowledge. Not exercised against a live Studio/TAC/TMC in this build. Items marked (unverified) are from memory only and should be checked in Studio before relying on exact labels.

Scope: every Studio Standard-Job component family that is NOT core DB/File/Processing
(components-core.md), NOT Spark-only (big-data-spark.md) and NOT ESB c*/tESB*/tREST*
service components (esb-routes-services.md). Palette family names below are the Studio
8.0 ones; 7.x names in brackets where they differ. Component labels are the exact
Basic/Advanced settings labels where a snippet confirmed them.

## Contents

- [How to use this file](#how-to-use-this-file)
- [TCK vs javajet connectors in Studio 8](#tck-vs-javajet-connectors-in-studio-8)
- [Authentication patterns](#authentication-patterns)
- [Proxy handling](#proxy-handling)
- [Cloud: Amazon](#cloud-amazon)
- [Cloud: Microsoft Azure](#cloud-microsoft-azure)
- [Cloud: Google](#cloud-google)
- [Snowflake](#snowflake)
- [Databricks and Delta Lake](#databricks-and-delta-lake)
- [Salesforce](#salesforce)
- [SaaS business apps](#saas-business-apps)
- [Microsoft Dynamics and legacy ERP/CRM](#microsoft-dynamics-and-legacy-erpcrm)
- [SAP](#sap)
- [NoSQL](#nosql)
- [Messaging](#messaging)
- [Internet](#internet)
- [XML, JSON, LDAP, Mail](#xml-json-ldap-mail)
- [Business Intelligence](#business-intelligence)
- [Talend Cloud and Data Fabric integration components](#talend-cloud-and-data-fabric-integration-components)
- [Data Mapper (tHMap)](#data-mapper-thmap)
- [Technical and misc connectors](#technical-and-misc-connectors)
- [Pipeline Designer connectors](#pipeline-designer-connectors)
- [Component availability by license](#component-availability-by-license)
- [Deprecated and removed connectors](#deprecated-and-removed-connectors)
- [Gotchas](#gotchas)
- [Sources](#sources)

## How to use this file

- Tables are `| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |`.
- "Connection/Close" pattern: every family with a `t<X>Connection` component exposes
  `Use an existing connection` + `Component List` on the other components; a matching
  `t<X>Close` (or `t<X>Commit`/`t<X>Rollback` for transactional stores) runs OnSubjobOk.
  Not repeated per row.
- "Die on error" (Basic settings) exists on nearly every component; clearing it routes the
  error to the component's `ERROR_MESSAGE` global and lets the subjob continue. Not repeated.
- Doc URL pattern (8.0): `https://help.qlik.com/talend/en-US/components/8.0/<family-slug>/<componentname-lowercase>`.
  7.3: `.../components/7.3/<family>/<component>-standard-properties`. Spark variants:
  `.../<component>-properties-for-apache-spark-batch|streaming`.
- Globals naming: `((Integer)globalMap.get("tS3Put_1_NB_LINE"))`, `..._ERROR_MESSAGE`,
  `..._CURRENT_STATUS` are the near-universal ones; family-specific ones are listed per table.

## TCK vs javajet connectors in Studio 8

Two component technologies coexist on the Studio 8.0 palette:

| Aspect | Legacy javajet components | Talend Component Kit (TCK) components |
| --- | --- | --- |
| Source | `*.javajet` templates in `plugins/org.talend.designer.components.localprovider/components/<tName>` | Java annotations (`@Processor`, `@Emitter`, `@DataStore`, `@DataSet`, `@Option`) packaged as a `.car` (component archive) per connector family |
| Delivery | Shipped in the Studio build; patched only by a Studio monthly update (R20YY-MM) | Shipped in the build AND re-deliverable independently via Feature Manager / "Talend Cloud" update site; some (tMarketoCampaign, tDataprepRun, tHMapInput, many newer SaaS) are not in the default install and show as "must be installed with the Feature Manager" |
| Metadata model | Flat property list; Repository > Metadata wizards are per-family hand-written | Two-level: a **datastore** (connection: endpoint + credentials) and a **dataset** (object/table/query/module on that connection). Repository > Metadata shows the connection node with datasets under it; both can be dragged on the canvas |
| Settings UI | Basic / Advanced settings, labels fixed in the javajet | Basic / Advanced derived from `@Option` layout; often an extra Repository-only "Dataset" entry; "Guess schema" is driven by the connector's discovery service |
| Dependencies | `IMPORT` entries in the component XML; Studio prompts "Install missing modules" for jars not on Maven Central / Talend update site (sapjco3, ojdbc, WebSphere MQ client, etc.) | Dependencies bundled in the `.car`, resolved into the Studio local m2 (`configuration/.m2/repository`); still show in Modules view and can require "Install missing modules" when the car was installed offline |
| Examples (8.0) | tFileInput*, tMysql*, tMap, tS3*, tRedshift*, tMongoDB*, tKafka*, tFTP*, tSendMail, tRESTClient, tSAP*, tLDAP*, tMom* | Salesforce (8.0 Salesforce family is TCK-based (unverified) ), Snowflake, Azure ADLS Gen2, Azure Storage (newer), Google (BigQuery TCK variants in Cloud), NetSuite (tNetSuite*), Marketo (REST), Workday, Couchbase, MarkLogic, Splunk (tSplunkEventCollector), Zendesk, Box, ServiceNow, Jira, tHTTPClient, tHMap I/O for Spark, tDataprepRun, tDataset* |
| Job generation | Component code inlined into the Job's generated Java | Job calls the `component-runtime` manager (`org.talend.sdk.component:component-runtime-manager`) which loads the car's classloader at runtime; stack traces show `org.talend.sdk.component.runtime.*` |
| Custom components | Build with Talend Component Designer / javajet, drop in `components/` user folder, or `Preferences > Talend > Components > User component folder` | Build with Component Kit starter (starter-toolkit.talend.io), `mvn talend-component:car`, then `java -jar <x>.car studio-deploy --location <studio>` or install via Feature Manager; see apis-sdks.md |

Operational points:

- Feature Manager: `Help > Feature Manager` (or top-bar button) after logging into a project.
  A feature is installed Studio-wide but **activated per project**; local projects activate it
  only in the current project, new projects get all installed features active. Default download
  source is the Talend official site; the repository URL is configurable (offline/air-gapped
  mirrors). Feature Manager is also where "Data Mapper for Spark", Bonita, Marketo campaign,
  Data Preparation, DQ extras etc. live.
- Studio monthly updates (`8.0.1-R2023-02`-style) carry both javajet patches and TCK car
  updates; many connector options are gated on an update ("available only if you have installed
  the 8.0.1-R2023-03 Talend Studio Monthly update or a later one"). Always state the R-version
  when a label is missing in a customer's Studio.
- "Install missing modules" / Modules view (`Window > Show View > Talend > Modules`): red
  entries are jars Studio cannot download automatically (license-restricted: sapjco3,
  IBM `com.ibm.mq.allclient`, Oracle, Teradata, DB2 in some versions, Neo4j 3.x bundles,
  Vertica). Install manually (browse the jar) or via `Install` button when a Talend-hosted URL
  exists. Build server / CI must have the same jars in its Nexus/Artifactory `talend-custom-libs`
  repository (see deployment-runtime.md).
- A TCK connector's version is pinned inside the Job item (`<elementParameter name="COMPONENT_VERSION">`-like
  field in the `.item`; see artifact-formats.md); opening a Job built with a newer car in an
  older Studio fails to load those components and shows them as unknown/red.
- Pure-password vs Java mode: newer TCK/javajet secret fields (8.0.1-R2022-05+) offer a
  "pure password" mode where the field holds a literal, and a Java mode where it is an
  expression (`context.secret`). Mixing them is a common cause of `Unknown variable` compile errors.

## Authentication patterns

| Pattern | Where it appears | Studio fields / mechanics | Notes |
| --- | --- | --- | --- |
| Basic (user/password) | Nearly all | `Username`, `Password` (password field encrypted in the item as `enc:` or via `context`) | Prefer `context` values loaded from TAC/TMC or `tContextLoad`; never commit literals |
| OAuth2 client credentials | tHTTPClient, tRESTClient (via `Use Authentication > OAuth2` (unverified)), Dynamics 365 (ONLINE), Azure AD service principal, Zendesk/ServiceNow (TCK: Basic or token), Marketo REST (client id/secret -> `identity/oauth/token`) | `Client ID`, `Client Secret`, `Token endpoint`/`Authority`, `Scope` | Marketo tokens live 1h; connector refreshes automatically. Dynamics uses `https://<org>.crm.dynamics.com/.default` scope |
| OAuth2 authorization code / ROPC | tMicrosoftCrm* (Authentication Code flow then ROPC, 8.0 late-2022 update), tGoogleDrive* Installed Application | Browser-based first consent; refresh token stored | Studio will open a browser once per credential set; headless build servers cannot do the first consent, do it in Studio first |
| JWT bearer (Salesforce) | tSalesforceConnection `Connection type`/`Login Type` = `OAuth` with `OAuth2 flow type` = `JWT Flow` (unverified exact labels) | `Issuer` (connected app client id), `Subject` (username), `Audience` (`https://login.salesforce.com` or `test.`), `Key Store`, `Key Store Password`, `Certificate Alias`, `Expiration time (seconds)`, `Token File` | Connected app needs "Use digital signatures" + pre-authorized profile/permission set; sandbox audience must be `test.salesforce.com` |
| Key pair (Snowflake) | tSnowflake* `Authentication Type = Key Pair` | `Private Key` (PEM path or content), `Private Key Passphrase`, `Key Alias` (unverified) | Public key registered with `ALTER USER ... SET RSA_PUBLIC_KEY`; PKCS8; unencrypted key needs blank passphrase |
| Service account JSON (Google) | tBigQuery*, tGS*, tGoogleDrive* `OAuth Method = Service Account`, tPubSub*, tDataproc* | `Service account key` / `Service account credentials file` = path to JSON file on the **job runtime** machine | Alternatively `GOOGLE_APPLICATION_CREDENTIALS` env var for ADC where the connector supports "Application Default Credentials" (BigQuery TCK, unverified) |
| AWS static keys | tS3*, tRedshift* bulk (S3 staging), tDynamoDB*, tSQS*, tKinesis*, tAmazonEMR* | `Access Key`, `Secret Key`; `Credential Provider = Static Credentials` | Signature V4 is implicit in SDK v1.11+/v2; specify `Region` explicitly for non-us-east-1 buckets |
| AWS IAM role / instance profile | tS3Connection `Credential Provider = Inherit credentials from AWS role` (7.3 R-update+, 8.0) | Reads EC2/EMR instance metadata; falls back from a named `Profile` to the role if the profile is missing | Only works when the Job runs on the EC2/EMR/ECS host; fails in Studio on a laptop |
| AWS STS assume role | tS3Connection `Assume Role` checkbox: `Role ARN`, `Role session name`, `Session duration`, `STS endpoint` (e.g. `sts.amazonaws.com`), optional `External Id`, `Serial number`/`Token code` for MFA (unverified subset) | Regional STS endpoint needed in VPC-endpoint setups | |
| AWS Web Identity Token / Profile | tS3Connection `Credential Provider = Web Identity Token` / `Profile` (`Profile name`, `~/.aws/credentials`) | EKS IRSA uses web identity | |
| Azure account key | tAzureStorage* `Authentication type = Basic`: `Account Name`, `Account Key`; tAzureAdlsGen2* `Authentication method = Shared key` | | |
| Azure SAS | tAzureStorage* `Use Azure Shared Access Signature` + `Azure Shared Access Signature` URL `https://<storagename>.<service>.core.windows.net/<sastoken>`; tAzureAdlsGen2* `Shared Access Signature`; Snowflake Azure stage `SAS Token` | SAS has an expiry and service/resource scope; blob vs file vs queue vs table SAS differ | |
| Azure AD service principal | tAzureStorage* `Authentication type = Azure Active Directory`: `Tenant ID`, `Client ID`, `Client Secret`; tAzureAdlsGen2* `Azure Active Directory`; tAzureSynapse*/tCosmosDB* (unverified) | Table storage does NOT support AAD (7.3 note) | |
| Azure managed identity | tAzureStorageConnection `Authentication type = Managed identities` (8.0.1-R2023-03+) | Only on Azure VMs/AKS/Remote Engine in Azure | |
| Databricks PAT | tDBFSConnection/tDBFSPut/tDBFSGet `Endpoint` (`https://adb-<id>.<n>.azuredatabricks.net`) + `Token`; tDeltaLake* JDBC URL `jdbc:databricks://...;PWD=<token>` | Token field click `[...]` | |
| NetSuite token-based auth (TBA) | tNetSuiteConnection `Login type = Token-based`: `Consumer key`, `Consumer secret`, `Token ID`, `Token secret`, `Account`, `Role` | Basic login is deprecated by NetSuite; TBA requires an Integration record and Access Token in NetSuite | |
| Kerberos keytab | tKafka* (`Use Kerberos authentication`, `JAAS configuration path`, `Kafka brokers principal name`, `Set kinit command path`, `Set Kerberos configuration path` (standard variant, unverified)), HBase/HDFS/Hive (big-data-spark.md), tMongoDB (`Authentication mechanism = KERBEROS` (unverified)), tSAP (SNC via JCo props) | JVM flag `-Djava.security.auth.login.config=jaas.conf`; `-Djava.security.krb5.conf=krb5.conf` | |
| SASL/PLAIN, SCRAM, SSL for Kafka | tKafkaConnection/Input/Output `Use SSL/TLS` + tSetKeystore, `Security protocol` (`SASL_PLAINTEXT`, `SASL_SSL`), `SASL mechanism` (PLAIN/SCRAM-SHA-256/512), JAAS via `Kafka properties` table | Confluent Cloud = SASL_SSL + PLAIN with API key/secret | |
| TLS keystore/truststore | tSetKeystore (`Set TrustStore`, `TrustStore type JKS/PKCS12`, `TrustStore file`, `TrustStore password`, `Need Client authentication`, `KeyStore type/file/password`); FTPS keystore on tFTPConnection; `Use SSL` on tMongoDB*, tCassandra*, tElasticSearch*, tNeo4j* | tSetKeystore sets JVM-wide `javax.net.ssl.*` system properties for the rest of the Job; not supported in ESB routes | |
| API key / token header | tZendeskInput/Output (`API token`), tServiceNow* (Basic or OAuth), tJIRAInput/Output (`Basic` user + API token), tSplunkEventCollector (`Token` for HEC), tBox* (OAuth JWT or developer token (unverified)), Dropbox (`Access Token`) | | |
| SSH key | tSCP*, tSSH, tFTPConnection SFTP `Authentication method = Public key` (`Private key`, `Key Passphrase`) or `Public key and password` | OpenSSH `ed25519` keys fail on old JSch (<0.1.55); convert to RSA PEM or update Studio | |

## Proxy handling

| Layer | How | Scope | Notes |
| --- | --- | --- | --- |
| Studio itself (update sites, Feature Manager, license, Talend Cloud login) | `Window > Preferences > General > Network Connections` (`Active Provider = Manual`, HTTP/HTTPS host:port, bypass list) or `-Dhttp.proxyHost=... -Dhttp.proxyPort=... -Dhttps.proxyHost=... -Dhttps.proxyPort=... -Dhttp.nonProxyHosts=...` in `Talend-Studio-*.ini` after `-vmargs` | Studio JVM only, not the Jobs it runs | Feature Manager failing with "Unable to read repository" = proxy or blocked `update.talend.com`/`talend-update.talend.com` |
| Job at design time and runtime | `tSetProxy` (family Internet > Proxy): `Proxy type` HTTP / HTTPS / SOCKS / FTP, `Proxy host`, `Proxy port`, `Proxy user`, `Proxy password`; option `Set a JVM proxy` (unverified label) | Sets `http.proxyHost` etc. JVM-wide for the rest of the Job run; place on a tPreJob or as first subjob | Not for ESB routes/data services (affects whole Talend Runtime). Does NOT apply to SFTP (JSch) - tFTPConnection docs: "SFTP Support does not work with an HTTPS proxy, use tSetProxy"; with HTTP proxy select `FTPS Support` + `Passive` mode |
| Per-component proxy | `Use or save proxy` / `Use proxy` + `Host`, `Port`, `User`, `Password` on tSalesforce*, tRESTClient, tHTTPClient, tSOAP, tFileFetch, tSendMail (unverified), tGoogleDrive*, tBox*, tMarketo*, tDropbox* (varies) | Component only | tSalesforce* `Use or save the connection session`/`Use Proxy` lives in Advanced settings |
| JVM args on launchers / TAC / TMC engines | Job `Run > Advanced settings > Use specific JVM arguments` (saved in the item and exported launcher), TAC task JVM parameters, Remote Engine `engine.sh`/`etc/org.talend.ipaas.rt.jobserver.client.cfg` or `JAVA_OPTS` | Whole process | `-Dhttp.nonProxyHosts="localhost|*.internal"` uses `|` separators |
| Couchbase | Couchbase SDK does not support proxies; tCouchbase* ignore tSetProxy | | |
| Authenticated proxies + Java 8u111+ | Basic auth to HTTPS proxies is disabled by default: add `-Djdk.http.auth.tunneling.disabledSchemes=` | | |

## Cloud: Amazon

Palette: `Cloud > Amazon > S3 | Redshift | DynamoDB | EMR | Aurora | MySQL | Oracle | Kinesis | SQS`.
Redshift/Aurora/AmazonMysql/AmazonOracle are JDBC families that follow the standard
DB pattern (Connection/Input/Output/Row/Commit/Rollback/Close, see components-core.md for
the shared Input/Output/Row parameters); only the Amazon-specific bits are listed here.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tS3Connection | Open a reusable S3 client | `Access Key`/`Secret Key`; `Credential Provider` (Static Credentials / Inherit credentials from AWS role / Web Identity Token / Profile); `Assume Role` (+ `Role ARN`, `Role session name`, `STS endpoint` e.g. `sts.amazonaws.com`); `Region`; Advanced: `Config client` table (`connectionTimeout`, `socketTimeout`, `maxConnections`, `protocol`, `signerOverride`, `proxyHost`...), `Use path-style access`, `Encrypt` (unverified), `Endpoint`/`Specify AWS S3 endpoint` for S3-compatible stores (MinIO) | javajet; Open Studio. Inherit-from-role requires the Job to run on the EC2/EMR host |
| tS3Put | Upload a local file (or stream) to a bucket/key | `Bucket`, `Key`, `File`; `Server-Side Encryption` (SSE-S3 / SSE-KMS `KMS key id`); `Enable Accelerate Mode`; `Upload from stream` (unverified); `Use ... connection` | Returns `KEY`, `BUCKET` globals (unverified) |
| tS3Get | Download object to local file | `Bucket`, `Key`, `File`; `Server-Side Encryption`; `Use a specific version` | |
| tS3List | List objects as rows | `List all buckets objects` or `Bucket`/`Key prefix` table; `Use path-style access` | Schema: `bucket`, `key`, `size`, `lastModified`, `storageClass`, `owner` (unverified); iterate via `Iterate` link with `((String)globalMap.get("tS3List_1_CURRENT_KEY"))`, `..._CURRENT_BUCKET` |
| tS3Delete | Delete object(s) | `Bucket`, `Key`(s) table | |
| tS3Copy | Server-side copy between buckets/keys | `Bucket`, `Key`, `Destination bucket`, `Destination key`, `Server-Side Encryption` | Objects >5 GB need multipart copy (handled by TransferManager in newer versions) |
| tS3BucketCreate / tS3BucketDelete / tS3BucketExist / tS3BucketList | Bucket admin | `Bucket`, `Region`/location constraint | tS3BucketExist sets `..._EXIST` boolean global (unverified) |
| tS3Close | Close connection | `Component List` | |
| tRedshiftConnection | JDBC connection | `Host`, `Port` 5439, `Database`, `Schema`, `Username`, `Password`; `Additional JDBC Parameters` (`ssl=true&sslfactory=...`); `Use SSO`/`Use IAM credentials`-style JDBC auth via `Driver version` (unverified) | javajet; Redshift JDBC 4.2 driver (`com.amazon.redshift.jdbc42.Driver`) downloaded by Studio |
| tRedshiftInput / tRedshiftOutput / tRedshiftRow / tRedshiftCommit / tRedshiftRollback / tRedshiftClose | Standard DB pattern | tRedshiftOutput: `Action on table` (Default / Drop and create / Create if not exists / Clear / Truncate), `Action on data` (Insert / Update / Insert or update / Update or insert / Delete), `Distribution style`/`Dist key`/`Sort key` on table create (unverified) | Row-by-row INSERT is slow on Redshift; use bulk for >10k rows |
| tRedshiftOutputBulk | Write delimited file and upload to S3 (no load) | `Data file path at local`, `Append local file`, S3: `Access Key`/`Secret Key`/`Bucket`/`Key`/`Region`; `Compress the data file` (gzip), `Encrypt`, field/row separators, `Text enclosure`, `Encoding` | javajet |
| tRedshiftBulkExec | Run `COPY` from S3 / EMR / DynamoDB / remote hosts (SSH manifest) | `Data source type` (S3 / EMR / DynamoDB / Remote host); `Table`, `Action on table`; `Key`/`Bucket`; `Date format`, `Time format`, `Delimiter`, `Null as`, `Ignore header`, `Compressed by` (GZIP/LZOP/BZIP2), `Encrypted`, `Fixed width`, `JSON`/`Avro` format options, `STATUPDATE`, `COMPUPDATE`, `MAXERROR` (unverified subset) | COPY needs the Redshift cluster IAM role or the key pair to read the bucket; cross-region needs `REGION` |
| tRedshiftOutputBulkExec | Generates delimited/CSV file, uploads to S3, loads with COPY in one component | Union of the two above; `Delete local file after load` (unverified) | Standard "bulk" idiom for Redshift loads |
| tRedshiftUnload | `UNLOAD (select) TO 's3://...'` | `Query`, S3 `Bucket`/`Key prefix`, `Access Key`/`Secret Key` or `IAM role`, `Parallel`, `Delimiter`, `Compressed by`, `Escape`, `Add quotes`, `Encrypted`, `Allow overwrite`, `Manifest` (unverified subset) | Output is N files `key000`, `key001`... unless `Parallel` off |
| tAmazonAuroraConnection / Input / Output / Row / Commit / Rollback / Close | Aurora MySQL via MySQL driver | `DB Version` (MySQL 5 / Aurora), `Additional JDBC Parameters` `noDatetimeStringSync=true` default | Aurora Postgres: use tPostgresqlInput family or tAmazonAuroraOutput "Postgres" variant (unverified) |
| tAmazonMysqlConnection / Input / Output / Row / Commit / Rollback / Close | RDS MySQL (same engine as tMysql* with Amazon endpoint) | Standard MySQL params | Functionally identical to tMysql*; kept for metadata clarity |
| tAmazonOracleConnection / Input / Output / Row / Commit / Rollback / Close | RDS Oracle | `Connection type` SID / Service Name; `Oracle version` | Needs ojdbc jar (Install missing modules) |
| tDynamoDBConnection / tDynamoDBInput / tDynamoDBOutput / tDynamoDBClose | Key-value NoSQL | `Access Key`/`Secret Key` or `Inherit credentials from AWS role`, `Region`, `Endpoint` (DynamoDB Local); tDynamoDBInput: `Table Name`, `Use advanced key condition expression` + `Key condition expression`, `Filter expression`, `Value mapping` table (`:placeholder` -> column); `Action on table`; tDynamoDBOutput: `Action on data` Insert / Update / Delete (unverified), `Partition Key`/`Sort Key` columns, `Read capacity`/`Write capacity` when creating | javajet; also Spark Batch variants (big-data-spark.md). Scan vs Query: without key condition it scans the whole table |
| tAmazonEMRManage | Create / terminate EMR clusters from a Job | `Action` (Create / Terminate), `Cluster name`, `Release label` (`emr-6.x`), `Applications`, `Instance type/count`, `EC2 key pair`, `Log URI`, `Service role`/`Job flow role`, `Visible to all users`, `Wait for cluster to be ready` (unverified subset) | Big Data license; pairs with `tAmazonEMRListInstances`/`tAmazonEMRResize` in older versions (unverified) |
| tKinesisInput / tKinesisOutput / tKinesisInputAvro | Kinesis Data Streams | `Stream name`, `Region`/`Endpoint`, `Access Key`/`Secret Key`; Input: `Shard iterator type` (TRIM_HORIZON / LATEST / AT_SEQUENCE_NUMBER) | **Spark Streaming only** in Studio (big-data-spark.md); no Standard Kinesis component. For Standard jobs use tHTTPClient against the REST API or a Route cAWS-KINESIS |
| tSQSConnection / tSQSInput / tSQSOutput / tSQSMessageDelete / tSQSMessageChangeVisibility / tSQSQueueCreate / tSQSQueueDelete / tSQSQueueList / tSQSQueueAttributes / tSQSQueuePurge / tSQSClose | Simple Queue Service | `Queue URL` or `Queue name`; `Access Key`/`Secret Key` or role; Input: `Max number of messages` (1-10), `Visibility timeout`, `Wait time seconds` (long polling), `Delete the message after receive`; Output: `Message body` column, `Delay seconds`, `Message group id`/`Deduplication id` (FIFO) | Standard family (7.1+). Message is a String; JSON must be parsed with tExtractJSONFields |

## Cloud: Microsoft Azure

Palette: `Cloud > Microsoft > Azure Storage Blob | Azure Storage Queue | Azure Storage Table | Azure Data Lake Storage Gen2 | Azure Synapse | Cosmos DB | Event Hubs`.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tAzureStorageConnection | Shared connection for Blob/Queue/Table components | `Account Name`; `Authentication type` Basic (`Account Key`) / Azure Active Directory (`Tenant ID`, `Client ID`, `Client Secret`) / Managed identities (8.0.1-R2023-03+); `Use Azure Shared Access Signature` + `Azure Shared Access Signature` (`https://<storagename>.<service>.core.windows.net/<sastoken>`); `Protocol` HTTPS/HTTP; `Endpoint suffix` (`core.windows.net`, `core.chinacloudapi.cn`, `core.usgovcloudapi.net`) | javajet (azure-storage SDK); Open Studio. Table storage does not support AAD |
| tAzureStorageContainerCreate / ContainerDelete / ContainerExist / ContainerList | Blob container admin | `Container name`, `Access control` (Private / Public container / Public blob) | ContainerExist sets `..._CONTAINER_EXIST` (unverified) |
| tAzureStoragePut | Upload local file(s) to blob | `Container name`, `Local folder`, `Azure Storage Folder`, `Use file list`/`Files` table with masks, `Keep existing file name`; `Blob type` Block / Append / Page (unverified) | Large files are chunked automatically |
| tAzureStorageGet | Download blobs | `Container`, `Local folder`, `Files` table (`Blob prefix`, `Include sub-directories`), `Keep remote folder structure`, `Die on error` | |
| tAzureStorageList | List blobs as rows / iterate | `Container`, `Blobs` table (prefix + include subdirs); globals `..._CURRENT_BLOB` | Iterate link to tAzureStorageGet per blob |
| tAzureStorageDelete | Delete blobs matching prefixes | `Container`, `Blobs` table | |
| tAzureStorageInputTable / tAzureStorageOutputTable | Azure Table storage rows | `Table name`; Input: `Use filter expression` (OData `PartitionKey eq 'x'`), `Name mappings`; Output: `Action on data` Insert / Insert or replace / Insert or merge / Merge / Replace / Delete, `Partition Key`/`Row Key` column mapping, `Process in batch` (100 max per batch, same partition) | No AAD auth (7.3 doc note) |
| tAzureStorageQueueCreate / QueueDelete / QueueList / QueueInput / QueueOutput / QueueInputLoop / QueuePurge | Azure Storage Queues | `Queue name`; QueueInput: `Number of messages` (<=32), `Peek`/`Delete the message`, `Visibility timeout`; QueueInputLoop: `Loop waiting time`; QueueOutput: `Time to live`, `Initial visibility delay` | Message body is String (base64 handled by SDK) |
| tAzureAdlsGen2Connection | ADLS Gen2 (DFS endpoint) | `Account Name`, `Endpoint suffix` (`dfs.core.windows.net`); `Authentication method` Shared key (`Shared key` field; pure-password or Java mode, 8.0.1-R2022-05+) / Shared Access Signature (`SAS token`) / Azure Active Directory (`Tenant ID`, `Client ID`, `Client Secret`; R2020-06+ on 7.3) ; 8.0 Output docs also describe Microsoft Fabric OneLake endpoints | TCK (Azure ADLS Gen2 connector `azure-dls-gen2`); Open Studio? No - subscription (unverified) |
| tAzureAdlsGen2Input / tAzureAdlsGen2Output | Read/write files in a filesystem path with schema | `Filesystem`, `Blob path`; `Format` CSV / Avro / JSON / Parquet (8.0) ; CSV: `Field delimiter`, `Record separator`, `Header`, `Encoding`, `Text enclosure`, `Escape`; Output: `Blob name template`, `Overwrite` | TCK; also Spark via tAzureFSConfiguration (big-data-spark.md) |
| tAzureAdlsGen2Get / tAzureAdlsGen2Put / tAzureAdlsGen2List / tAzureAdlsGen2Delete | File transfer and listing against ADLS Gen2 paths | `Filesystem`, `Blob path`, `Local folder`, `Recursive`, `Files` table; Delete has `Recursive` | TCK |
| tAzureSynapseConnection / Input / Output / Row / Commit / Rollback / Close / BulkExec / OutputBulk / OutputBulkExec | Synapse SQL pool (dedicated/serverless) via mssql JDBC | `Host` (`<ws>.sql.azuresynapse.net`), `Port` 1433, `Database`, `Authentication` SQL password / Azure AD password / Service principal (unverified subset); BulkExec: `COPY INTO` from ADLS/Blob (`Azure Storage` account, container, `Authentication` SAS/Storage key/Managed identity), `File format` CSV/Parquet | Formerly `tAzureSqlDWH*` (Azure SQL Data Warehouse) in 7.x; renamed Synapse in 7.3/8.0; old names remain as deprecated aliases (unverified). Subscription |
| tCosmosDBConnection / tCosmosDBInput / tCosmosDBOutput / tCosmosDBRow / tCosmosDBBulkLoad / tCosmosDBSQLAPIInput / tCosmosDBSQLAPIOutput / tCosmosDBClose | Cosmos DB | MongoDB API components mirror tMongoDB* (`Action on data`, `Mapping` with `Parent node path`); `Host` `<acct>.documents.azure.com`, `Port` 10255, `Use SSL`, `Database`, `Username`=account, `Password`=key; SQL API components: `Endpoint`, `Primary key`, `Database`, `Collection`, Input `Query` (SQL), Output `Action on data` Create / Upsert / Delete (unverified) | javajet; Mongo-API variants need Cosmos account created with MongoDB API |
| tAzureEventHubsInput / tAzureEventHubsOutput | Event Hubs (Kafka-compatible) | `Namespace`, `Event hub name`, `SAS key name`/`SAS key` or connection string; Input: `Consumer group` (`$Default`), `Receiver position` (start/end/offset/enqueued time), `Checkpoint store` (blob) (unverified) | 8.0 family, TCK-based (unverified). Alternative: tKafka* with `SASL_SSL`/`PLAIN` + connection string `$ConnectionString` against `<ns>.servicebus.windows.net:9093` |
| tAzureFSConfiguration | Spark-only filesystem config for ADLS/Blob | see big-data-spark.md | Spark |
| tMicrosoftOneLake* (unverified) | Fabric OneLake | per 8.0 ADLS Gen2 Output doc, OneLake is reached via ADLS Gen2 components with `onelake.dfs.fabric.microsoft.com` endpoint | |

## Cloud: Google

Palette: `Cloud > Google > BigQuery | Google Storage | Google Drive | Pub/Sub | Dataproc | Bigtable`.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tBigQueryConnection | Shared BigQuery client | `Project ID`; `Authentication mode`/`Credential type` Service account (default in 8.0; `Service account key` JSON file via `[...]`) / OAuth 2.0 Access Token / Application Default Credentials (8.0, unverified) ; `Use Google Cloud Storage` staging settings for bulk | javajet (google-api-services-bigquery) with a TCK rewrite in later 8.0 R-updates (unverified) |
| tBigQueryInput | Run a query and stream rows | `Query` (Standard SQL; `Use legacy SQL` checkbox), `Result size` (Small = synchronous `jobs.query`, Large = `allowLargeResults` to a temp/destination table (unverified)), `Dataset location` / `Location` (EU/US/region - must match dataset) | Query cost = bytes scanned; timestamps come back as String/Long epoch depending on version |
| tBigQueryOutput | Write rows via GCS + load job (not streaming inserts) | `Dataset`, `Table`, `Action on data` Truncate / Append / Empty (unverified labels), `Bucket`, `File` (`gs://my_bucket/my_file.csv`, must be directly under bucket root), `Bulk file already exists in Google storage`, `Create directory if not exists`, `Table operation` Create if not exist / Drop and create / Truncate (unverified) | Writes a local CSV then uploads; needs Storage Object Admin on the bucket + BigQuery Data Editor + Job User |
| tBigQueryBulkExec | Load an existing GCS file into a table | `Bucket`, `File`, `Dataset`, `Table`, `Action on data`, `Field delimiter`, `Header rows to skip`, `Encoding`, `Allow quoted newlines`, `Source format` CSV/JSON/Avro/Parquet (unverified) | |
| tBigQueryOutputBulk | Write the local/GCS file only | Delimited file options | Pair with tBigQueryBulkExec |
| tBigQuerySQLRow | Execute DDL/DML without a flow (CREATE/MERGE/DELETE) | `Query`, `Dataset location`, `Propagate QUERY's recordset` (unverified) | Use for MERGE-based upserts; BigQuery has no row-level UPDATE from tBigQueryOutput |
| tBigQueryClose | Close | | |
| tGSConnection | Google Cloud Storage client | `Access Key`/`Secret Key` (HMAC interoperability keys, legacy javajet) or `Service account` JSON (8.0) | javajet; HMAC keys are per-user/per-service-account under Cloud Storage > Settings > Interoperability |
| tGSPut / tGSGet / tGSList / tGSDelete / tGSCopy | Object transfer and listing | `Bucket`, `Key`/`Object key`, `Local file`/`Local folder`, `Files` masks; List: `Bucket`, `Key prefix`, globals `..._CURRENT_KEY`/`..._CURRENT_BUCKET` | |
| tGSBucketCreate / tGSBucketDelete / tGSBucketExist / tGSBucketList | Bucket admin | `Bucket`, `Location`, `Storage class` (unverified) | |
| tGSClose | Close | | |
| tGoogleDriveConnection | Drive client | `OAuth Method`: Installed Application (Id & Secret) (`Client ID`, `Client Secret`, `Application Name`, `Data store path` for refresh token), Installed Application (JSON) (`Client secret JSON`), Service Account (`Service account JSON`); `Use Proxy`, `Use SSL` (unverified) | javajet; first run of Installed Application opens a browser consent at design time |
| tGoogleDriveCreate / tGoogleDrivePut / tGoogleDriveGet / tGoogleDriveCopy / tGoogleDriveDelete / tGoogleDriveList | Folder create, upload, download, copy, delete, list | `File name`/`Folder`/`Parent folder` by name or `Use folder ID`/`Access method` (By Name / By Id); Put: `Local file`, `Overwrite`, `Replace if existing`, `Upload mode` (Upload file / Expose as output stream / Read from input stream (unverified)); Get: `Export format` for Google Docs/Sheets (CSV/PDF/XLSX...); List: `Folder`, `Include subfolders`, `List mode` Files / Directories / Both; `Include trashed` (unverified) | Service accounts see only files shared with their email or in Shared Drives (`Include shared drives` option on newer versions, unverified) |
| tPubSubInput / tPubSubOutput / tPubSubInputAvro | Pub/Sub | `Project`, `Topic`, `Subscription` (Input), `Service account` JSON; Output `Message body`/`Attributes`; Input `Subscription type` Create if not exists (unverified) | **Spark Streaming only** in Studio (big-data-spark.md). Standard jobs: tHTTPClient to `pubsub.googleapis.com/v1/...:publish` or Route cGoogle... (none) |
| tGoogleDataprocManage | Create/delete Dataproc clusters | `Action`, `Project`, `Cluster name`, `Region`/`Zone`, `Image version`, `Master/Worker machine type`, `Number of workers`, `Service account` JSON | Big Data license; pairs with Spark Job `Dataproc` distribution (big-data-spark.md) |
| tBigtableInput / tBigtableOutput | Cloud Bigtable | `Project ID`, `Instance ID`, `Table`, `Service account`, Output `Column family` mappings | 8.0 (TCK, unverified); Spark variants exist |
| tGoogleAnalyticsInput (deprecated) | GA Core Reporting API v3 | `View ID`, `Dimensions`/`Metrics`, service account | Deprecated/removed with GA Universal Analytics EOL (2023); no GA4 component - use tHTTPClient against Data API v1 |

## Snowflake

Palette `Cloud > Snowflake`. TCK-based since 7.1 (connector id `snowflake`); Open Studio includes
the basic set (unverified), bulk/stage components are subscription. All components share the
connection block below or `Use an existing connection` from tSnowflakeConnection.

Connection block: `Account` (locator or `org-account`), `Snowflake Region` (legacy; prefer full
account identifier), `User Id`, `Authentication Type` Basic (`Password`) / Key Pair (`Private Key`,
`Private Key Passphrase`) / OAuth 2.0 (`Token` or client id/secret + `OAuth token endpoint`, 8.0
R-update) ; `Warehouse`, `Schema`, `Database`, `Role`; Advanced: `Login Timeout` (minutes),
`Tracing`, `Allow Snowflake to convert columns and tables to uppercase`, `Additional JDBC
Parameters` (`application=TALEND&...`), `Use custom region`/`Custom Region` (unverified).

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tSnowflakeConnection | Shared JDBC session | Connection block above; `Use custom Snowflake region` | TCK |
| tSnowflakeInput | Read from table or query | `Table Name` + `Condition` (WHERE clause) or `Manual Query`/`Query`; `Guess schema` via `Snowflake table` dropdown; Advanced: `Convert columns and table to uppercase`, `Fetch size` (unverified) | Timestamps mapped to `java.util.Date`; `TIMESTAMP_TZ` loses zone unless read as String |
| tSnowflakeOutput | Row-level DML via JDBC batches | `Table`, `Table Action` None / Drop and create / Create / Create if not exists / Drop if exists and create / Clear / Truncate (unverified labels); `Output Action` Insert / Update / Upsert / Delete; `Upsert Key Column`; Advanced: `Use Schema Date Pattern`, `Date Pattern`, `Convert empty strings to null`, `Use custom DB type` (unverified) | Internally stages via `PUT`+`COPY` for Insert with `Use batch`? No - plain JDBC; for >100k rows use OutputBulkExec |
| tSnowflakeRow | Execute arbitrary SQL (`CALL proc()`, `MERGE`, `COPY INTO`) | `Query`, `Propagate QUERY's recordset`, `Die on error`, `Commit every` (unverified) | Session parameters like `ALTER SESSION SET TIMEZONE` via tSnowflakeRow on same connection |
| tSnowflakeOutputBulk | Write rows to a stage file (no COPY) | `Storage` Internal (`Stage Folder`) / S3 (`Region`, `Access Key`, `Secret Key`, `Bucket`, `Folder`) / Azure (`Protocol`, `Account Name`, `Container`, `Folder`, `SAS Token`); file options `Field Separator`, `Compress` (gzip), `Encoding`, `Use Custom Stage Path`/`Stage Name` (`@~`, `@%table`, `@mystage`) | TCK; S3 keys here are the stage keys, not the connection |
| tSnowflakeBulkExec | `COPY INTO` from existing staged files | Same `Storage` block; `Table`, `Table Action`, `Load Action` (unverified), `Copy Command Options` (`ON_ERROR=CONTINUE`, `PURGE=TRUE`, `FORCE`, `MATCH_BY_COLUMN_NAME`), `Delete Storage Files On Success`, `File Format` CSV/JSON/AVRO/PARQUET (unverified) | Monitor `COPY_HISTORY`/`LOAD_HISTORY` for rejects |
| tSnowflakeOutputBulkExec | Stage + COPY in one | Union of the two above | Standard Snowflake load idiom; Internal stage = no cloud credentials needed |
| tSnowflakeCommit / tSnowflakeRollback / tSnowflakeClose | Transaction + close | `Close Connection` on Commit | Autocommit is ON by default on the JDBC driver unless `Auto Commit` unchecked on tSnowflakeConnection (unverified) |
| tSnowflakeInputTable (unverified) | Older TCK dataset-style input using Repository dataset | | Appears in some 7.x builds; superseded by tSnowflakeInput |
| Snowflake metadata wizard | `Repository > Metadata > Snowflake` stores connection (datastore) and lets you `Retrieve Schema` of tables/views (dataset) | | TCK datastore/dataset model |

## Databricks and Delta Lake

Palette `Cloud > Databricks` (DBFS) and `Databases > Delta Lake` (JDBC). Spark-on-Databricks
cluster execution is in big-data-spark.md.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tDBFSConnection | REST client to DBFS | `Endpoint` (`https://adb-<id>.<n>.azuredatabricks.net` or AWS workspace URL), `Token` (Personal Access Token via `[...]`) | javajet; subscription (Big Data) |
| tDBFSPut / tDBFSGet / tDBFSDelete | Upload/download/delete files on `dbfs:/` | `DBFS directory`, `Local directory`, `Files` masks, `Overwrite`; Get: `Keep remote structure` (unverified) | Uses DBFS REST API `/api/2.0/dbfs/*` (1 MB blocks); not suitable for TB loads - use cloud storage + mount |
| tDeltaLakeConnection / tDeltaLakeInput / tDeltaLakeOutput / tDeltaLakeRow / tDeltaLakeClose | SQL against Databricks SQL warehouse / cluster via Databricks JDBC | `JDBC URL` must start with `jdbc:databricks://` from 8.0.1-R2023-05 (older `jdbc:spark://` jobs need manual edit); `httpPath=/sql/1.0/warehouses/<id>`; `AuthMech=3;UID=token;PWD=<PAT>`; add `EnableArrow=0` to avoid Log4j2 conflict errors; Output: `Action on data` Insert / Update / Delete / Merge (unverified), `Table action` | javajet, DB family. Delta Lake Spark components (`tDeltaLakeInput/Output` in Spark Batch) are different: big-data-spark.md |
| Databricks Unity Catalog | 3-level names `catalog.schema.table` in `Table` field; `ConnCatalog`/`ConnSchema` JDBC params | | 8.0 R2023+ (unverified) |
