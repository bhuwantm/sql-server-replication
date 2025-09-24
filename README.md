# SQL Server Transactional Replication with Docker Compose

This project demonstrates SQL Server transactional replication using Docker Compose with two SQL Server instances - a Publisher and a Subscriber.

## 🏗️ Architecture

```
┌─────────────────┐    Replication    ┌─────────────────┐
│   Publisher     │ ─────────────────► │   Subscriber    │
│ (sqlserver-     │                    │ (sqlserver-     │
│  publisher)     │                    │  subscriber)    │
│ Port: 1440      │                    │ Port: 1434      │
└─────────────────┘                    └─────────────────┘
         │                                       │
         └─────────────────┬─────────────────────┘
                           │
                  ┌─────────────────┐
                  │   Adminer       │
                  │ (Web Interface) │
                  │ Port: 8080      │
                  └─────────────────┘
```

## 📋 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 4GB RAM available for containers
- SQL Server client tools (optional, for direct connection)

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd sqlserver-replication
```

### 2. Configure Environment

Edit the `.env` file if needed (default password is already set):

```bash
# View current configuration
cat .env

# Optionally modify the SA password
# SA_PASSWORD=YourStrong!Passw0rd
```

### 3. Start the Environment

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 4. Wait for Services to Initialize

The SQL Server instances need time to start and initialize. Wait for the health checks to pass:

```bash
# Check health status
docker-compose ps

# Wait for both services to be healthy (about 2-3 minutes)
```

### 5. Setup Replication

#### Step 5a: Create Database and Sample Data

```bash
# Run on both instances (database creation)
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/shared/01-create-database.sql -C

docker exec -it sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/shared/01-create-database.sql -C
```

#### Step 5b: Configure Publisher

```bash
# Configure the publisher
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/publisher/02-setup-publisher.sql -C
```

#### Step 5c: Configure Subscriber

```bash
# Configure the subscriber
docker exec -it sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/subscriber/03-setup-subscriber.sql -C
```

### 6. Test Replication

```bash
# Generate test data on publisher
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/shared/06-test-data.sql -C

# Check data on subscriber (should appear within seconds)
docker exec -it sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "USE ReplicationDemo; SELECT COUNT(*) as CustomerCount FROM Customers; SELECT COUNT(*) as ProductCount FROM Products; SELECT COUNT(*) as OrderCount FROM Orders; -C"
```

## � Connection Details

### **Database Connections**
- **Publisher**: `localhost:1440` (sa/YourStrong!Passw0rd)
- **Subscriber**: `localhost:1434` (sa/YourStrong!Passw0rd)
- **Web Interface**: `http://localhost:8080` (Adminer)

### **Quick Connection Commands**
```bash
# Connect to Publisher
sqlcmd -S localhost,1440 -U sa -P 'YourStrong!Passw0rd'

# Connect to Subscriber  
sqlcmd -S localhost,1434 -U sa -P 'YourStrong!Passw0rd'
```

## �🔧 Management Commands

### Using Helper Scripts

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Setup everything automatically
./scripts/setup-replication.sh

# Monitor replication status
./scripts/monitor-replication.sh

# Generate test data
./scripts/generate-test-data.sh

# Cleanup environment
./scripts/cleanup.sh
```

### Manual SQL Server Connections

#### Connect to Publisher

```bash
# Using Docker exec
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd'

# Using external client (if you have sqlcmd installed)
sqlcmd -S localhost,1440 -U sa -P 'YourStrong!Passw0rd'
```

#### Connect to Subscriber

```bash
# Using Docker exec
docker exec -it sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd'

# Using external client
sqlcmd -S localhost,1434 -U sa -P 'YourStrong!Passw0rd'
```

#### Using Adminer (Web Interface)

1. Open http://localhost:8080 in your browser
2. Select "SQL Server" as the system
3. For Publisher: Server = `sqlserver-publisher`, Username = `sa`, Password = `YourStrong!Passw0rd`
4. For Subscriber: Server = `sqlserver-subscriber`, Username = `sa`, Password = `YourStrong!Passw0rd`

## 📊 Monitoring Replication

### Check Replication Status

```bash
# Run monitoring script
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -i /opt/sql/shared/05-monitor-replication.sql -C
```

### Key Metrics to Monitor

1. **Replication Agent Status**: Ensure snapshot and distribution agents are running
2. **Pending Commands**: Check for any undistributed transactions
3. **Replication Errors**: Monitor for any replication failures
4. **Data Consistency**: Verify data is synchronized between publisher and subscriber

## 🗂️ Project Structure

```
sqlserver-replication/
├── docker-compose.yml          # Main Docker Compose configuration
├── .env                        # Environment variables
├── .gitignore                  # Git ignore patterns
├── README.md                   # This documentation
├── scripts/                    # Helper scripts
│   ├── setup-replication.sh    # Automated setup script
│   ├── monitor-replication.sh  # Monitoring script
│   ├── generate-test-data.sh   # Test data generation
│   └── cleanup.sh             # Cleanup script
└── sql/                       # SQL scripts directory
    ├── shared/                # Scripts for both instances
    │   ├── 01-create-database.sql    # Database and table creation
    │   ├── 05-monitor-replication.sql # Monitoring queries
    │   └── 06-test-data.sql          # Test data generation
    ├── publisher/             # Publisher-specific scripts
    │   ├── 02-setup-publisher.sql    # Publisher configuration
    │   └── 04-setup-push-subscription.sql # Push subscription setup
    └── subscriber/            # Subscriber-specific scripts
        └── 03-setup-subscriber.sql   # Subscriber configuration
```

## 🔬 Sample Database Schema

The project includes a sample e-commerce database with the following tables:

- **Customers**: Customer information
- **Products**: Product catalog
- **Orders**: Order headers
- **OrderDetails**: Order line items

All tables are configured for transactional replication.

## 🛠️ Troubleshooting

### Common Issues

#### 1. Container Health Check Failures

```bash
# Check container logs
docker-compose logs sqlserver-publisher
docker-compose logs sqlserver-subscriber

# Verify SA password is correct
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "SELECT @@VERSION -C"
```

#### 2. Replication Setup Failures

```bash
# Check SQL Server Agent is running
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "EXEC msdb.dbo.sp_help_job -C"

# Verify replication components
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "SELECT * FROM sys.servers -C"
```

#### 3. Network Connectivity Issues

```bash
# Test connectivity between containers
docker exec -it sqlserver-subscriber ping sqlserver-publisher

# Check network configuration
docker network ls
docker network inspect sqlserver-replication_replication-network
```

#### 4. Replication Not Working

```bash
# Check publication status
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "USE ReplicationDemo; SELECT * FROM syspublications -C"

# Check subscription status
docker exec -it sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "USE ReplicationDemo; SELECT * FROM syssubscriptions -C"

# Reinitialize subscription if needed
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "USE ReplicationDemo; EXEC sp_reinitsubscription @publication = N'ReplicationDemo_Publication', @article = N'all' -C"
```

### Performance Tuning

1. **Increase Memory**: Modify `docker-compose.yml` to allocate more memory
2. **Optimize Snapshot**: Consider using backup-based initialization for large databases
3. **Batch Size**: Adjust distribution agent batch size for better throughput
4. **Network**: Ensure low latency between publisher and subscriber

## 🔄 Maintenance

### Backup and Restore

```bash
# Backup publisher database
docker exec -it sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q "BACKUP DATABASE ReplicationDemo TO DISK = '/var/opt/mssql/data/ReplicationDemo.bak' -C"

# Copy backup file from container
docker cp sqlserver-publisher:/var/opt/mssql/data/ReplicationDemo.bak ./ReplicationDemo.bak
```

### Cleanup

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (WARNING: This deletes all data)
docker-compose down -v

# Clean up images
docker image prune
```

## 📚 Additional Resources

- [SQL Server Replication Documentation](https://docs.microsoft.com/en-us/sql/relational-databases/replication/)
- [Docker SQL Server Documentation](https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment)
- [Transactional Replication Best Practices](https://docs.microsoft.com/en-us/sql/relational-databases/replication/administration/best-practices-for-replication-administration)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🔧 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review SQL Server error logs in container logs
3. Consult SQL Server replication documentation
4. Open an issue in this repository

---

**Note**: This setup is intended for development and testing purposes. For production use, consider additional security measures, monitoring, and backup strategies.
