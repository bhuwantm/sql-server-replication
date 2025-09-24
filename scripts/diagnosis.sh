#!/bin/bash

echo "🔍 Diagnosing SQL Server Publisher Health Issues"
echo "=============================================="

# Check if containers are running
echo "📊 Container Status:"
docker-compose ps

echo ""
echo "📋 Publisher Container Logs (last 30 lines):"
docker logs sqlserver-publisher --tail 30

echo ""
echo "🔍 Health Check Status:"
docker inspect sqlserver-publisher --format='{{.State.Health.Status}}' 2>/dev/null || echo "Health check info not available"

echo ""
echo "🔌 Testing Manual Connection to Publisher:"
if docker exec sqlserver-publisher /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q 'SELECT 1' -C 2>/dev/null; then
    echo "✅ Manual connection to publisher works - health check configuration issue"
else
    echo "❌ Manual connection to publisher failed - SQL Server startup issue"
fi

echo ""
echo "🔌 Testing Manual Connection to Subscriber:"
if docker exec sqlserver-subscriber /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'YourStrong!Passw0rd' -Q 'SELECT 1' -C 2>/dev/null; then
    echo "✅ Manual connection to subscriber works"
else
    echo "❌ Manual connection to subscriber failed"
fi

echo ""
echo "💾 System Resources:"
echo "Memory:"
free -h 2>/dev/null || echo "Memory info not available"
echo "Disk space:"
df -h . 2>/dev/null || echo "Disk info not available"

echo ""
echo "🐳 Docker Status:"
docker system df 2>/dev/null || echo "Docker system info not available"

echo ""
echo "🔍 Diagnosis Complete!"
