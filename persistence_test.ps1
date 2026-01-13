Write-Host "Step 1: Clearing Elasticsearch indices..."
try {
    Invoke-RestMethod -Method Delete -Uri "http://localhost:9200/_all" -ErrorAction SilentlyContinue
} catch {
    Write-Host "ES might be down or empty, proceeding..."
}

Write-Host "Step 2: Stopping Elasticsearch..."
docker compose stop elasticsearch

Write-Host "Step 3: Sending 100 log messages..."
$payload = @{message="persistence test"; extra=@{important="true"}} | ConvertTo-Json
for ($i=1; $i -le 100; $i++) {
    try {
        $null = Invoke-RestMethod -Method Post -Uri "http://localhost:8000/log" -Body $payload -ContentType "application/json"
    } catch {
        Write-Host "Failed to send request $i"
    }
}
Write-Host "Sent 100 messages."

Write-Host "Step 4: Restarting Logstash (Simulating restart with queued data)..."
docker compose restart logstash
# Wait for Logstash to stop and start again
Start-Sleep -Seconds 10

Write-Host "Step 5: Starting Elasticsearch..."
docker compose start elasticsearch

Write-Host "Step 6: Waiting for data to drain..."
# Wait for ES to come up and Logstash to drain
$retries = 0
while ($retries -lt 30) {
    Start-Sleep -Seconds 2
    try {
        $count = (Invoke-RestMethod -Method Get -Uri "http://localhost:9200/_count?q=message:persistence" -ErrorAction SilentlyContinue).count
        Write-Host "Current document count: $count"
        if ($count -eq 100) {
            Write-Host "SUCCESS: 100 documents found! Queue persisted."
            exit 0
        }
    } catch {
        Write-Host "Waiting for ES/Logstash..."
    }
    $retries++
}

Write-Host "FAILED: Did not find 100 documents."
exit 1
