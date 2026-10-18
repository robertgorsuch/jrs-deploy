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

## Salesforce

Palette `Business > Salesforce`. Studio 7.x/8.0 family is TCK-based (connector `salesforce`,
Partner WSDL + Bulk API); the 6.x javajet set had the same names. Components share a connection
block or `Use an existing connection` to tSalesforceConnection.

Connection block: `Connection type`/`Login Type` Basic (`User Id`, `Password`, `Security Key`
= security token appended to password) / OAuth (`OAuth2 flow type` JWT Flow or Implicit Flow:
`Client Id`, `Client Secret`, `Callback Host`/`Callback Port` (implicit), `Token File`; JWT:
`Issuer`, `Subject`, `Audience`, `Key Store`, `Key Store Password`, `Certificate Alias`,
`Expiration time`); `Salesforce URL` (`https://login.salesforce.com/services/Soap/u/<version>`,
`test.salesforce.com` for sandboxes); `API version` (e.g. `57.0`; the URL and the field must
agree); Advanced: `Timeout (milliseconds)`, `Use Proxy`/`Use or save proxy` (`Host`, `Port`,
`User`, `Password`), `Use HTTP Chunked`, `Client Id` (connected app name shown in Salesforce
login history), `Retry` settings (unverified labels), `Use SOAP compression`.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tSalesforceConnection | Shared session (one login) | Block above; `Bulk Connection` checkbox (unverified) when the session will be used by Bulk components | Open Studio includes Salesforce. A session configured for Bulk must be paired with Bulk query mode; Query mode works only with non-bulk connections (community answer) |
| tSalesforceInput | SOQL read | `Module Name` (sObject; `Use custom module` for custom objects `Foo__c`), `Query Mode` Query / Bulk / BulkV2; `Query condition` (WHERE) or `Manual Query` (full SOQL, `Guess query`/`Guess schema`), `Include deleted records` (queryAll), `Column Name Delimiter` for relationship fields (`Account.Name` -> `Account_Name`), `Normalize Delimiter` for child relationship subqueries; Advanced: `Safety Switch` (unchecked allows >10k rows in-memory for relationships), `Batch Size` (QueryOptions 200-2000), `Use Soap Compression`, `Convert date to local`/`Use Date Pattern` (unverified) | Bulk: async CSV job (`Job Id` global), PK chunking NOT supported by the component; BulkV2 7.3 R-update+, needs API 41+; community error "Number of records should be less than or equal to 10001" when a Bulk batch result exceeds the CSV parser limit |
| tSalesforceOutput | Row-level DML via SOAP | `Module Name`, `Output Action` Insert / Update / Upsert / Delete; `Upsert Key Column` (External ID field); Advanced: `Extend Insert` (batch up to `Commit Level` rows per call, default 200), `Retrieve Insert Id` / `Retrieve Salesforce ID` (adds `salesforce_id` to output; only available when Extend Insert is OFF), `Ignore Null`, `Use Soap Compression`, `Reject`/`Main` output flows with `errorCode`/`errorFields`/`errorMessage` columns (unverified exact names), `Log File` | Hard-delete not available (SOAP delete -> recycle bin). Extend Insert off = 1 API call per row (slow; community: 9 min vs seconds) but per-row rejects |
| tSalesforceOutputBulk | Write a local CSV in Bulk API format | `Bulk File Path`, `Append`, `Ignore Null`, `Relationship mapping for upsert` table (polymorphic lookup `Account:External_Id__c`) | Pair with tSalesforceBulkExec |
| tSalesforceBulkExec | Submit CSV via Bulk API | `Module Name`, `Action` Insert / Update / Upsert / Delete / Hard delete (unverified), `Upsert Key Column`, `Bulk File Path`, `Bytes To Commit`/`Rows To Commit` per batch (max 10 MB / 10,000 rows), `Concurrency Mode` Parallel / Serial, `Wait Time Check Batch State`, `Bulk API V2`, `Use Content Type` CSV/JSON (unverified), outputs Main (successes with `salesforce_id`, `salesforce_created`) and Reject (`error`) | Bulk API limits: 15,000 batches / 24h (classic), 150 MB per V2 job |
| tSalesforceOutputBulkExec | OutputBulk + BulkExec | Union | Standard high-volume load idiom |
| tSalesforceGetServerTimestamp | Returns server time | Output schema `ServerTimestamp` (Date) | Use to stamp incremental loads consistently (UTC) |
| tSalesforceGetDeleted | `getDeleted(module, start, end)` | `Module Name`, `Start Date`, `End Date` (ISO `yyyy-MM-dd'T'HH:mm:ss'Z'` or Date), schema `Id`, `deletedDate` | Window max 30 days back and <= 30 days wide (Salesforce API limit) |
| tSalesforceGetUpdated | `getUpdated(module, start, end)` | Same; returns `Id` list then join with tSalesforceInput | Same window limits; minute granularity |
| tSalesforceEinsteinBulkExec / tSalesforceEinsteinOutputBulk / tSalesforceEinsteinOutputBulkExec | Push datasets to Einstein Analytics (CRM Analytics / Wave) via External Data API | `Dataset Name`, `Operation` Overwrite / Append / Upsert / Delete, `Edgemart Container` (app), `Metadata JSON` (auto-generated from schema), `Notification` settings | Subscription; Wave/Einstein naming retained |
| tSalesforceWaveBulkExec (old name) | Same as Einstein | | 6.x alias |
| Salesforce metadata wizard | `Repository > Metadata > Salesforce`: connection + `Retrieve Salesforce Modules` (datasets) | | TCK datastore/dataset |

## SaaS business apps

Palette `Business > Marketo | NetSuite | Workday | ServiceNow | Zendesk | Box | Dropbox | JIRA | Splunk`.
Most are TCK connectors delivered in 7.1+ and updated through Feature Manager / R-updates.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tMarketoConnection | Marketo REST/SOAP session | `API Mode` REST (default) / SOAP (legacy, removed 8.0, unverified); `Endpoint address` (`https://<munchkin>.mktorest.com/rest`), `Client Access ID`, `Secret key` (Admin > LaunchPoint > View Details; endpoint under Admin > Web Services); Advanced: `Timeout`, `Max reconnection attempts`, `Attempt interval time` | TCK-ish (javajet with REST client) (unverified). `Repository > Metadata > Marketo` wizard exists (8.0 R2024-05 doc "Centralizing Marketo metadata") |
| tMarketoInput | Read leads, activities, lead changes, custom objects, companies, opportunities | `Operation` getLead / getMultipleLeads / getLeadActivity / getLeadChanges / getCustomObjects / describeCustomObject / listCustomObjects / getCompanies / getOpportunities (REST); `Lead Key Type` (email, id, cookie, ...), `Lead Key Values`, `List Param` (STATIC_LIST_NAME/ID), `Include Types` (activity type ids), `Since Date Time`/`Paging token`, `Batch Size` (<=300 REST), `Fields` mapping | REST quota 50,000 calls/day and 100 calls / 20 s per instance; `Max reconnection attempts` handles 606 rate-limit codes |
| tMarketoOutput | Sync leads / custom objects | `Operation` syncLead / syncMultipleLeads / syncCustomObjects / deleteCustomObjects / syncCompanies / deleteCompanies / syncOpportunities...; `Operation type`/`Action` createOnly / updateOnly / createOrUpdate / createDuplicate; `Lookup field` (`email`, `id`, `Munchkin cookie`), `De-dupe by`; `Batch Size` (<=300) | Main + Reject outputs with `Status`/`ERROR_MSG` |
| tMarketoListOperation | addToList / removeFromList / isMemberOfList | `List Param` STATIC_LIST_NAME / STATIC_LIST_ID, `List Param Value`, `Lead Key Type`, `Multiple Operation` | |
| tMarketoBulkExec | Bulk import leads/custom objects from a local CSV (REST bulk import API) | `Bulk Import To` Leads / CustomObjects, `Bulk File Path`, `Lookup Field`, `List Id`, `Partition Name`, `Log Download Path` (failures/warnings CSV), `Poll wait time`, `Timeout` | 8.0; async job with status polling; 10 MB per file, 10 concurrent jobs (Marketo limits) |
| tMarketoCampaign | Trigger/schedule smart campaigns, get campaigns | `Campaign action` getCampaigns / getCampaignById / scheduleCampaign / triggerCampaign (unverified), `Campaign Id`, `Lead Ids`, `Tokens` table, `Clone to program` | Not installed by default; install via Feature Manager |
| tNetSuiteConnection | NetSuite SOAP (SuiteTalk) session | `Version` NetSuite Deprecated (2019 component) / Netsuite SOAP (2019/2021/2025 component); `Endpoint` (`https://<acct>.suitetalk.api.netsuite.com/services/NetSuitePort_2025_1`), `Login type` Basic (`Email`, `Password`, `Role`, `Account`, `Application ID`) / Token-based (`Consumer key`, `Consumer secret`, `Token ID`, `Token secret`); `Account`, `Role` | Component named `tNetSuiteV2019Connection/Input/Output` until 8.0.1-R2023-02, then folded back into `tNetSuiteConnection/Input/Output` with the `Version` switch; original `tNetsuiteInput`/`tNetsuiteOutput` (lowercase s, API 2014.2/2016.2) are `(deprecated)` pages in 8.0 |
| tNetSuiteInput | Search a record type | `Record Type` (standard and custom records, fetched from the account), `Search Condition` table (`Field`, `Operator`, `Value`, join sub-record fields), `Body fields only` (skip sublists for speed), `Use custom fields`/`Custom fields` (resolved from `customFieldList`), `Page size` (<=1000), `Saved search` support via `Search Condition` on `savedSearchId` (unverified) | SuiteTalk concurrency governance: default 1 concurrent request per account unless SuiteCloud Plus; 429/`WS_REQUEST_BLOCKED` on parallel subjobs |
| tNetSuiteOutput | add / update / upsert / delete records | `Action` Add / Update / Upsert / Delete, `Record Type`, `Use Native Upsert` (external id), `Batch size` (<=100 per `addList`), custom fields mapping, Reject flow with `errorCode`/`errorMessage` | |
| tWorkdayInput | Read from Workday | `Authentication mode` OAuth 2.0 client credentials (`Tenant alias`, `Client ID`, `Client Secret`, `Authentication endpoint`) / SOAP - Login (`User`, `Password`); `Mode` Workday Query Language (WQL: `Query`), Report As A Service (`Report Owner`, `Report Name`, extra `Parameters`), Workday web services (8.0: `Service`, `Operation`, request XML); `Service endpoint` (`https://<host>/ccx/`) | TCK (`workday`), 7.3+. RaaS only takes effect with SOAP - Login auth mode (8.0 doc). RaaS URL `https://<host>/ccx/service/customreport2/<tenant>/<owner>/<Report_Name>` |
| tServiceNowInput / tServiceNowOutput | Table API | `Instance URL` (`https://<inst>.service-now.com`), `Authentication` Basic / OAuth 2.0 (`Client ID`, `Client Secret`, user+password ROPC); Input: `Table` (`incident`, `sys_user`, `cmdb_ci`), `Query` (encoded query `active=true^priority=1`), `Fields`, `Max records`/`Limit`, `Exclude reference link`, `Display value` (unverified); Output: `Action` Insert / Update / Delete, `Sys ID` column | TCK (`servicenow`), 7.0+ |
| tZendeskInput / tZendeskOutput | Zendesk Support API | `Server URL` (`https://<sub>.zendesk.com`), `Authentication` Basic / API Token (`Username/token` style) / OAuth token; Input: `Selection` Tickets / Users / Organizations / Requests..., `Query` (Search API syntax), `Resolve references`; Output: Create / Update / Delete on same objects | TCK (`zendesk`), 7.0+ |
| tBoxConnection / tBoxGet / tBoxPut / tBoxDelete / tBoxList / tBoxCopy | Box content | `Authentication` OAuth 2.0 with JWT (`Client ID`, `Client Secret`, `Enterprise ID`, `Public key ID`, `Private key`, `Passphrase`) via Box app config JSON, or `Developer token` (unverified); `Folder`/`File` by path or ID, `Overwrite`, `Local file` | TCK (`box`), 7.x; Box app must be authorized by the enterprise admin |
| tDropboxConnection / tDropboxGet / tDropboxPut / tDropboxDelete / tDropboxList | Dropbox v2 API | `Access Token` (long-lived or refresh via `App key`/`App secret`, unverified); `Path`, `Local file`, `Upload mode` (Upload entire file / Chunked, `Chunk size`), `Overwrite`/`Rename on conflict` | javajet (dropbox-core-sdk); Open Studio |
| tJIRAInput / tJIRAOutput | Jira Cloud/Server REST | `Host URL`, `Authentication` Basic (`User`, `Password`/API token) / PAT (unverified); Input: `Resource` Issue / Project, `JQL`/`Issue id`, `Batch size`; Output: `Action` Create / Update / Delete, `Resource`, JSON body column | TCK (`jira`), 7.0+ |
| tSplunkEventCollector | Send events to Splunk HTTP Event Collector | `Server URL` (`https://<host>:8088`), `Token` (HEC token), `Extended Event Metadata` (`index`, `source`, `sourcetype`, `host`, `time` columns), `Batch size`, `Disable SSL verification` (unverified) | TCK (`splunk`), 7.0+. Output-only; no Splunk search input component |

## Microsoft Dynamics and legacy ERP/CRM

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tMicrosoftCrmInput | Query Dynamics CRM / 365 entities | `Authentication Type` ON_PREMISE / ONLINE; `CRM Version` 2011 / 2015 / 2016 / 2018 (Dynamics 365) (unverified subset); ON_PREMISE: `Mode` NTLM / OAUTH 2.0, `Service root URL`/`Security Service URL` (ADFS/STS), `Domain`, `Username`, `Password`, `Max connection retries`; ONLINE: `Registered application type` Native App / Web App with delegated permissions, `Application ID`/`Client ID`, `Client Secret`, `OAuth authorization endpoint`, `Username`/`Password` (ROPC) with Authentication Code flow used first to obtain the token (8.0 late-2022 R-update); `Entity` (`account`, `contact`, custom `new_foo`), `Query` (FetchXML or `Filter` conditions via `Conditions` table, `Logical operator`), `Order by`; Advanced: `Reuse Http Client`, `Lookup mapping` (`Lookup type`, `Reference entity`) | javajet (odata-client for 2016+); Open Studio? subscription (unverified). AADSTS7000218 = client secret missing for a Web App registration |
| tMicrosoftCrmOutput | Create / Update / Delete entities | Same auth; `Action` Insert / Update / Delete; `Entity`; `Lookup mapping` table: `Input Column`, `Lookup Type` (entity logical name) for `EntityReference` columns; `Ignore Null`; Reject flow with `errorMessage` | Web API (2016+) uses `@odata.bind` for lookups |
| tMSAXInput / tMSAXOutput (Dynamics AX) | Dynamics AX 2012 via AIF .NET Business Connector | `Server`, `Company`, `Language`, `Table`, `Connection via .NET` | Deprecated/removed in 8.0 (Windows-only Business Connector); use OData/tHTTPClient against D365 F&O |
| tSugarCRMInput / tSugarCRMOutput | SugarCRM (SOAP v2/v4 API) | `Server URL` (`.../soap.php`), `Username`, `Password`, `Module` (Accounts, Contacts...), Output `Action` Insert / Update (via `id`) | Legacy javajet, Open Studio; SOAP API removed in Sugar 7+ -> use tHTTPClient against REST v11 |
| tVtigerCRMInput / tVtigerCRMOutput | vtiger CRM 5.x webservice | `Endpoint`, `Username`, `Access key`, `Module` | Legacy, unmaintained; Open Studio |
| tOpenbravoERPInput / tOpenbravoERPOutput | Openbravo ERP REST (XML) | `Endpoint`, `User`, `Password`, `Entity`/`Table` | Deprecated 7.x, removed 8.0 (unverified) |
| tCentricCRMInput / tCentricCRMOutput | Centric CRM (ConcourseSuite) | | Removed years ago (5.x era); only in very old exports |
| tSalesforceWave* | see Salesforce | | |
| tMicrosoftMQInput / tMicrosoftMQOutput | MSMQ via COM/.NET bridge | `Queue path` `.\private$\name` | Windows only; deprecated/removed in 8.0 (unverified) |
| SharePoint / Exchange | No native Studio components | Use tHTTPClient against Microsoft Graph (`/sites/{id}/drives`, `/users/{id}/messages`) with OAuth2 client credentials, or Route cMSGraph (none) | Pipeline Designer and Qlik Cloud have SharePoint/OneDrive connectors; Studio does not |

## SAP

Palette `Business > SAP`. Subscription-only (Data Integration / Data Fabric; Open Studio has no
SAP). All need `sapjco3.jar` + native `libsapjco3.so`/`sapjco3.dll` (SAP JCo 3.x, downloaded from
SAP Support Portal with S-user; Studio prompts "requires sapjco.jar" -> Install missing modules,
and the native lib must be on `java.library.path` / `PATH` / `LD_LIBRARY_PATH` of Studio,
JobServer and Remote Engine). IDoc components additionally need `sapidoc3.jar`. Table/BW streaming
needs the **Talend SAP RFC Server** (separate installer, `$TSAPS_HOME`; connections under
`$TSAPS_HOME/conf/named-connections` (doc snippet spelled "named-connectiond")), used as a
streaming proxy so large extractions avoid FTP/SFTP staging; its ABAP side needs the Talend
transport (`Z_TALEND_*` function modules) imported into the SAP system.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tSAPConnection | JCo client connection | `Connection type` Application server (`Host`, `System number`, `Client`, `User`, `Password`, `Language`) / Message server (load balancing: `Message host`, `R3 name`, `Group`) ; `SAP Properties` table (any `jco.client.*` prop: `jco.client.snc_mode=1`, `jco.client.snc_partnername`, `jco.client.saprouter`, `jco.client.peak_limit`) ; `Use SAP router` | javajet; repository wizard `Metadata > SAP Connections` retrieves BAPIs, tables, IDoc types, BW objects |
| tSAPBapi | Call a BAPI/RFC with import/export/table/changing parameters, or document-type (XML) input | `Function Name` (e.g. `BAPI_CUSTOMER_GETLIST`, `BAPI_TRANSACTION_COMMIT`), `Input mapping` (parameter -> column or `Document` XML), `Output mapping` (output tables -> schemas, one output flow per table), `Use Document type parameter`, `Commit after each BAPI call`/`BAPI_TRANSACTION_COMMIT` (unverified) | Metadata wizard generates the schema per table parameter; `tSAPCommit` not needed when using BAPI_TRANSACTION_COMMIT |
| tSAPTableInput | Read a table/view with a filter | `Table name` (`MARA`, `KNA1`, `/BI0/PMATERIAL`), `Where clause`/`Filter condition` (ABAP OpenSQL syntax, 72-char line split handled), `Fields` (schema = selected columns), `Batch size`/`Rows per package`, `Use RFC Server`/`Streaming via Talend SAP RFC Server` (`RFC server host/port`, `Program ID`), `Row skips`/`Row count` (unverified subset) | Classic `RFC_READ_TABLE` limited to 512 bytes/row; Talend's `Z_TALEND_READ_TABLE` (via transport) removes the limit |
| tSAPIDocInput (deprecated) / tSAPIDocOutput / tSAPIDocReceiver | IDoc send/receive | Output: `IDoc type` (`DEBMAS07`), `Message type`, `Document` XML input flow (built with tXMLMap / tWriteXMLField from the wizard-generated IDoc schema), `Receiver port`/`Partner profile`; Receiver: registers as RFC server (`Program ID`, `Gateway host/service`, `Repository destination`), `Wait time`, outputs IDoc XML | tSAPIDocInput marked deprecated in 7.2; tSAPIDocReceiver is a listener component (runs until timeout/stop) |
| tSAPCommit / tSAPRollback | BAPI transaction control on a shared tSAPConnection | `Component List`, `Close Connection` | |
| tSAPDSOInput / tSAPDSOOutput | BW DataStore Object (classic DSO) read/write | `DSO name`, `Active table`/`Changelog`, filter | BW 7.x; RFC Server optional for streaming |
| tSAPADSOInput | BW/4HANA Advanced DSO read | `ADSO name`, `Table type` Active / Inbound (unverified), filter | Requires Talend transport + RFC server (unverified) |
| tSAPInfoObjectInput / tSAPInfoObjectOutput | BW InfoObject master data (attributes/texts/hierarchies) | `InfoObject`, `Data type` Attributes / Texts / Hierarchy | |
| tSAPInfoCubeInput | BW InfoCube (MDX via BAPI_MDPROVIDER / OpenHub style) | `InfoCube`, `MDX`/characteristics and key figures selection | Prefer ODP or ADSO on BW/4 |
| tSAPODPInput | Operational Data Provisioning (extractors, CDS views, BW objects) with delta | `Subscriber name`, `Context` (SAPI / ABAP_CDS / BW / HANA), `ODP name`, `Extraction mode` Full / Delta init / Delta, `Package size`, `Fields`, `Filter` | 7.3+; delta queue state kept per subscriber in SAP (ODQMON) |
| tSAPDataSourceReceiver / tSAPDataSourceOutput | Receive data pushed from a BW DataSource (3rd-party BW source system) / write to BW | `DataSource`, `Source system` (Talend registered as 3rd-party system via `RSA1`), RFC server `Program ID`; Output: `Target InfoProvider`, `Request handling` | Talend acts as the BW source system; requires BW admin setup |
| tSAPBWInput | Generic BW read (OpenHub destination table or MDX) | `Query`/`OpenHub destination` | Older component; DSO/ADSO/InfoCube/ODP are the focused successors |
| tSAPHanaConnection / Input / Output / Row / Commit / Rollback / Close / BulkExec / OutputBulk / OutputBulkExec / tSAPHanaInvalidRows / tSAPHanaValidRows / tSAPHanaUnload / tSAPHanaInvalidRows | SAP HANA as a JDBC database | `Host`, `Port` 3xx15, `Database`/`Schema`, `ngdbc.jar` driver; BulkExec = `IMPORT FROM CSV FILE` on server-side path (unverified) | DB family in `Databases > SAP HANA`; see components-core.md for shared params |
| tSAPIDocInput, tSAPBWInput, tSAPInfoCubeInput | Pointer: BW on HANA replacement is ODP/CDS | | |

## NoSQL

Palette `Databases > NoSQL` (8.0) / `Big Data > NoSQL` (7.x). Most families: javajet with a
`DB Version` dropdown that selects the driver jar set; many also have Spark variants (big-data-spark.md).
HBase/Hive/HCatalog are in big-data-spark.md.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tMongoDBConnection | Shared Mongo client | `DB Version` (3.x / 4.x driver; 8.0 adds 4.4+/5/6 via `mongo-java-driver` 4.x), `Use replica set address` + `Replica set` table (host/port rows; `Set read preference` Primary / Secondary / Nearest...), `Server`/`Port` 27017, `Database`, `Use SSL` (truststore via tSetKeystore), `Required authentication` + `Authentication mechanism` NEGOTIATE / PLAIN_SASL (LDAP) / SCRAM-SHA-1 / SCRAM-SHA-256 / KERBEROS / X.509 (unverified subset) + `Authentication database`, `Username`, `Password`; `Use connection string` (`mongodb+srv://...`) in newer 8.0 R-updates (unverified) | javajet; Open Studio. Atlas needs `mongodb+srv` (DNS seedlist) -> use connection string option or list all replica hosts with `Use SSL` |
| tMongoDBInput | Query a collection | `Collection`, `Query` (JSON `{ "status": "A", "qty": { "$gt": 25 } }`), `Mapping` table (`Column`, `Parent node path` for nested docs), `Sort by` table, `Limit`, `No query timeout`, `Aggregation pipeline`/`Use aggregation framework` (JSON stages, 7.x+), `Set read preference`, `Allow disk use` | Non-schema fields are dropped; use a single `Document`/`String` column + tExtractJSONFields for schemaless reads |
| tMongoDBOutput | Write documents | `Collection`, `Drop collection if exists`, `Action on data` Insert / Set / Upsert / Upsert with set / Update / Delete / Bulk write (unverified last), `Mapping` table (`Column`, `Parent node path`, `Remove null field` (unverified)), `Append to parent` (Set adds field to the parent node in Mapping), `Insertable`/`Updatable` columns (Upsert with set; R2020-08+), `Query`/`Keys` columns (which schema columns form the match filter; 7.2 used `Data node`/`Query node` on a JSON tree), `Bulk write` + `Bulk write size`, `Ordered`, `Write concern` (unverified) | `_id` as ObjectId: map a String column named `_id`; Upsert needs the key column in both Query and Mapping |
| tMongoDBRow | Run `db.runCommand` / JavaScript-ish command JSON | `Function`/`Command` JSON, `Execute command` or `Use a function` (unverified) | For `createIndex`, `renameCollection`, `aggregate` with `$out` |
| tMongoDBBulkLoad | Wrapper around `mongoimport` binary | `Mongoimport path`, `Data file`, `File type` JSON / CSV / TSV, `Action on data` Insert / Upsert, `Upsert fields`, `Drop`, `Headerline`, `Ignore blanks`, `Fields` | Needs mongo tools installed on the Job host |
| tMongoDBGridFSGet / tMongoDBGridFSPut / tMongoDBGridFSDelete / tMongoDBGridFSList / tMongoDBGridFSProperties | GridFS file store | `Bucket` (`fs`), `Query` (JSON on `filename`/metadata), `Local folder`, `Files` masks, `Metadata` table on Put | |
| tMongoDBClose | Close | | |
| tCassandraConnection / tCassandraInput / tCassandraOutput / tCassandraRow / tCassandraOutputBulk / tCassandraBulkExec / tCassandraOutputBulkExec / tCassandraClose | Cassandra CQL3 | `DB Version` (Cassandra 2.0 deprecated (Thrift `API type` CQL/Thrift) / 2.2 / 3.x / 4.x via `datastax java-driver`), `Host`, `Port` 9042, `Keyspace`, `Username`/`Password`, `Use SSL`, `Datacenter`/`Load balancing policy`; Input: `Query` (CQL, `Use query`), `Column family`/`Table`, `Consistency level`; Output: `Action on keyspace` / `Action on column family`, `Action on data` Insert / Update / Delete, `Replication` (`SimpleStrategy`/`NetworkTopologyStrategy`, `Replication factor`), `Use TTL`/`TTL column`, `Insert if not exists`, `Batch size`/`Use unlogged batch`, `Consistency level`; Bulk: `SSTable` generation + `sstableloader` path | javajet; Open Studio. DataStax Astra needs secure-connect bundle -> not supported; use tJDBC with Astra JDBC or REST |
| tNeo4jConnection / tNeo4jInput / tNeo4jOutput / tNeo4jRow / tNeo4jBatchOutput / tNeo4jBatchOutputRelationship / tNeo4jBatchSchema / tNeo4jImportTool / tNeo4jOutputRelationship / tNeo4jClose | Neo4j graph | `DB Version` Neo4j 2.x (embedded `Database path` or REST `Server URL`) / 3.x (Bolt `bolt://host:7687`, `Username`/`Password`) / 4.x+ (8.0 R-updates, `neo4j://` routing, unverified); Input: `Query` (Cypher `MATCH (n:Person) RETURN n.name`), `Mapping` of return columns; Output: `Node label`/`Index`, `Mapping`, `Create relationship` (`Relationship type`, `Direction`, start/end key columns), `Batch size`, `Commit every`; Row: Cypher DDL/DML (`CREATE INDEX`); BatchOutput: unsafe fast CSV import for new DBs | javajet; does not support 3.2.x (doc note); never mix 2.x and 3.x components in one Job (class conflict). Neo4j 5 Aura: use tJDBC with Neo4j JDBC driver or tHTTPClient (unverified) |
| tElasticSearchInput / tElasticSearchOutput / tElasticSearchConfiguration / tElasticSearchLookupInput | Elasticsearch index read/write | `Nodes` (`host:port` list), `Transport` HTTP (9200) / Node (9300, removed in ES 8) (unverified), `Index`, `Type` (removed ES 7+, `_doc`), `Use authentication` (`Username`/`Password`, API key via headers (unverified)), `Use SSL`; Input: `Query` (JSON query DSL), `Scroll size`/`Page size`; Output: `Action` Index / Upsert / Delete, `Id column`, `Batch size`/`Bulk size`, `Refresh` | Standard variants exist (7.x+, javajet, `elasticsearch-rest-client`) but most docs are Spark Batch/Streaming (big-data-spark.md). OpenSearch works over HTTP with Basic auth for ES 7-compatible versions |
| tCouchbaseConnection / tCouchbaseInput / tCouchbaseOutput / tCouchbaseClose (and Spark variants) | Couchbase Server bucket/collection | `Bootstrap nodes` (`couchbase://host1,host2`), `Bucket`, `Scope`/`Collection` (7.x server), `Username`/`Password` (RBAC), `Connection timeout`; Input: `Use N1QL query` + `Query` (`SELECT META().id, * FROM bucket WHERE ...`), or `Document type` JSON / String / Binary; Output: upserts documents built from flat input (`Id field`, `Generate document id`, `Content format` JSON / String / Binary, `Partial update` (sub-document), `Use N1QL query` for arbitrary DML), `Query parameters` mapping | TCK (`couchbase`), 7.1+; Couchbase SDK does not support proxies so tSetProxy is ignored |
| tCouchDBInput / tCouchDBOutput / tCouchDBConnection / tCouchDBClose | Apache CouchDB (HTTP) | `Server`, `Port` 5984, `Database`, `Username`/`Password`; Input: `Use view`/`Design document`/`View name` or `Document id`, `Mapping`; Output: `Action` Insert / Update / Delete, `Bulk documents` | Legacy javajet (ektorp); low maintenance; Open Studio |
| tMarkLogicConnection / tMarkLogicInput / tMarkLogicOutput / tMarkLogicBulkLoad / tMarkLogicClose | MarkLogic document database | `Host`, `Port` (REST app server 8000+), `Database`, `Username`/`Password`, `Authentication` Digest / Basic (unverified); Input: `Criteria`/`Query` (string query or structured), `Page size`, `Document type` XML / JSON / Text / Binary -> `docContent` column; Output: `Action` Upsert / Patch / Delete, `Doc id` column, `Collections`; BulkLoad: wraps MLCP (`MLCP path`, `Input file path`, `Input type`, `Output URI prefix`, extra `-options`) | TCK (`marklogic`), 7.1+; "available in Talend products with Big Data and in Talend Data Fabric" |
| tRedisConnection / tRedisInput / tRedisOutput / tRedisClose / tRedisKeyList (unverified) | Redis key-value | `Host`, `Port` 6379, `Password`, `Database index`, `Use cluster`/`Sentinel` (unverified); Input: `Key pattern`, `Data type` String / Hash / List / Set / ZSet; Output: `Action` Set / HSet / RPush / SAdd / ZAdd / Delete, `TTL` | Standard components exist in 7.x subscription palette (`Big Data > NoSQL > Redis`, javajet, Jedis) (unverified); also Spark Streaming variants |
| tDynamoDB* | see Cloud: Amazon | | |
| tCosmosDB* | see Cloud: Microsoft Azure | | |
| Amazon DocumentDB | Use tMongoDB* with `Use replica set` + `Use SSL` (RDS CA bundle in truststore) + SCRAM-SHA-1 | | No dedicated family |
| tRiakInput / tRiakOutput / tRiakConnection (deprecated) | Riak KV | `Node`, `Bucket`, `Key` | Deprecated 6.x, removed 7.x/8.0 (unverified) |
| ArangoDB, Aerospike, ScyllaDB | No native components | tJDBC (ArangoDB JDBC), tCassandra* for Scylla (CQL-compatible), tHTTPClient | |
| tHBase*, tHive*, tHCatalog*, tHDFS*, tSqoop*, tImpala* | Hadoop ecosystem | big-data-spark.md | |

## Messaging

Palette `Internet > Kafka | JMS | MOM | MQTT | RabbitMQ` (8.0; 7.x had `Big Data > Kafka`).
Standard components are listed; Spark Streaming counterparts carry the same names and are
documented in big-data-spark.md.

| Component | Purpose | Key settings / auth | Notes (license, version, TCK vs javajet) |
| --- | --- | --- | --- |
| tKafkaConnection | Shared broker config | `Version` (Kafka client 0.9/0.10/1.x/2.x/3.x per Studio release), `Broker list` (`host1:9092,host2:9092`), `Use SSL/TLS` (+ tSetKeystore), `Use Kerberos authentication` (`JAAS configuration path`, `Kafka brokers principal name`, `Kerberos configuration path`, `Set kinit command path`), `Kafka properties` table (`security.protocol=SASL_SSL`, `sasl.mechanism=PLAIN`, `sasl.jaas.config=...`, `ssl.endpoint.identification.algorithm=`) | javajet; Open Studio has Kafka Standard components (unverified); Spark versions need Big Data |
| tKafkaInput | Consume messages (String or byte[]) | `Topic name`, `Consumer group id` (created at runtime if absent), `Reset offsets on consumer group` (discard committed offsets), `New consumer group starts from` beginning / latest (only used when the group has no committed offset), `Auto-commit offsets` + `Interval` or manual commit via tKafkaCommit, `Stop after a maximum number of messages`/`Stop after receiving a maximum number of messages`, `Stop after a maximum total duration (ms)`, `Stop after a maximum time without receiving a message (ms)`, `Max poll records`, `Output type` String / byte[] (`Serializer`), `Consumer properties` table (`max.partition.fetch.bytes`, `isolation.level=read_committed`); Advanced: `Load the offset with the message` (adds `offset`/`partition`/`key`/`timestamp` columns, unverified) | Runs forever unless a `Stop after...` option is set; use with `Iterate`-less flow into tMap/tExtractJSONFields. Job-script key `AUTO_OFFSET_RESET_NEW` = EARLIEST/LATEST |
| tKafkaOutput | Produce | `Topic name`, `Compress the data` (gzip/snappy/lz4/zstd), `Serializer` String/byte[], `Key` column (`Set a key column` / `Use key`), `Producer properties` table (`acks=all`, `enable.idempotence=true`, `linger.ms`, `batch.size`, `max.request.size`) | Message = one input row's single column (String/byte[]); build JSON upstream with tWriteJSONField |
| tKafkaCommit | Commit consumer offsets of a tKafkaInput on the same connection | `Component List` (the tKafkaInput) | Place after the processing subjob to get at-least-once semantics |
| tKafkaCreateTopic | Admin create topic | `Topic`, `Partitions`, `Replication factor`, `Action on topic` Create / Create if not exists, `Topic properties` (`retention.ms`) | 7.x+ |
| tKafkaInputAvro | Consume Avro with schema | `Avro schema`/Schema Registry URL (`schema.registry.url` in properties) | Spark Streaming only (big-data-spark.md); for Standard jobs decode Avro bytes with tExtractAvroFields? No - use tJavaRow + Confluent deserializer or tKafkaInput byte[] + routine |
| tJMSInput / tJMSOutput | Generic JMS 1.1 via JNDI | `Context Provider` (`org.apache.activemq.jndi.ActiveMQInitialContextFactory`, `com.sun.jndi.fscontext.RefFSContextFactory` for IBM MQ bindings, `org.jboss.naming.remote.client.InitialContextFactory`, `org.apache.qpid.jms.jndi.JmsInitialContextFactory` for AMQP 1.0), `Server URL` (`tcp://host:61616`, `file:/path/.bindings`), `Connection Factory JNDI Name` (`ConnectionFactory`), `Use Specified User Identity` (`User`, `Password`), `Message Type` Queue / Topic, `To`/`From` (destination name; ActiveMQ `dynamicQueues/foo` style via JNDI props), `Message Selector` (SQL92), `Timeout`, `Maximum Messages`, `Processing Mode` Raw message / Message content (unverified), `Properties` table (JNDI env), `Durable subscription`/`Client ID` (Topic), Output: `Delivery mode` Persistent / Non persistent, `Priority`, `Time to live`, `Message properties` table, `Reply to` (unverified); Advanced: `Transacted`/`Acknowledgement mode` AUTO / CLIENT / DUPS_OK | javajet; Open Studio. The JMS provider client jars (activemq-all, com.ibm.mq.allclient + jms.jar, artemis-jms-client) must be added via `Modules`/tLibraryLoad; mismatched versions = `ClassNotFoundException`/`NoSuchMethodError` at runtime |
| tMomConnection / tMomInput / tMomOutput / tMomCommit / tMomRollback / tMomClose / tMomMessageIdList (unverified) | Vendor-specific MOM shortcuts | `MQ Server` ActiveMQ / JBoss Messaging / WebSphere MQ; `Host`, `Port` (61616 / 1414), `Username`/`Password`; WebSphere MQ only: `QueueManager`, `Channel` (default `DC.SVRCONN`), `MessageQueue`, `Set Transacted`, `Target client` MQ / JMS (unverified), `CCSID`; ActiveMQ: `Failover` (`failover:(tcp://a,tcp://b)`), `Static Discovery`, `Transport options` table; Input: `Message Type` Queue/Topic, `To`/`From`, `Timeout`, `Maximum messages`, `Message body type` String / byte[] (`Use byte[]`), `Get message id`/`Get message headers`; Output: `Message` column, `Delivery mode` | javajet; IBM MQ needs `com.ibm.mq.allclient.jar` (not downloadable by Studio; license). 8.0 docs also list newer `tMessagingInput`/`tMessagingOutput` (JMS family) that delegate to "Configure JMS producers / WebSphere MQ connector" pages (unverified details) |
| tMessagingInput / tMessagingOutput | 8.0 unified messaging (JMS/WMQ) components | `Connection` type, `Destination`, `Message format`; see 8.0 `mom`/`jms` family pages | 8.0 R-update additions (unverified scope) |
| tRabbitMQInput / tRabbitMQOutput / tRabbitMQConnection / tRabbitMQClose (unverified names) | AMQP 0-9-1 | `Host`, `Port` 5672, `Virtual host`, `Username`/`Password`, `Use SSL`; Input: `Queue`, `Auto ack`/`Prefetch`, `Stop after N messages`; Output: `Exchange`, `Routing key`, `Durable`, `Message properties` | Standard RabbitMQ components exist only in newer 8.0 R-updates / Routes (`cMQ`/`cRabbitMQ`) (unverified); classic workaround is tJMSInput with Qpid JMS AMQP 1.0 client or Route cAMQP |
| tMQTTInput / tMQTTOutput | MQTT 3.1.1 (Eclipse Paho) | `Broker URL` (`tcp://host:1883`, `ssl://...`), `Topic`, `QoS` 0/1/2, `Client ID`, `Username`/`Password`, `Clean session`, `Retained` (Output) | Spark Streaming components in Studio; Standard MQTT via Route `cMQTT` (esb-routes-services.md). No Standard tMQTT* (unverified) |
| tPubSubInput / tPubSubOutput, tKinesisInput / tKinesisOutput | Google Pub/Sub, AWS Kinesis | Spark Streaming only (see Cloud sections) | |
| tAzureEventHubsInput / tAzureEventHubsOutput | Event Hubs | see Cloud: Microsoft Azure | |
| tSQS* | AWS SQS Standard components | see Cloud: Amazon | |
| IBM MQ | tMomInput/Output `MQ Server = WebSphere MQ` (native MQ classes) or tJMSInput/Output with `.bindings` JNDI file (`com.sun.jndi.fscontext.RefFSContextFactory`) created by `JMSAdmin`; Route `cMQConnectionFactory` + `cJMS`/`cWMQ` | | |
| cKafka, cJMS, cMQTT, cAMQP, cMQConnectionFactory | Route (Camel) messaging components | esb-routes-services.md | cKafka `Auto Offset Reset` EARLIEST / LATEST / NONE |
