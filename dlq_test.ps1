Write-Host "Step 1: Stopping Logstash..."
docker compose stop logstash

Write-Host "Step 2: Cleaning up indices..."
try {
    Invoke-RestMethod -Method Delete -Uri "http://localhost:9200/logstash-*" -ErrorAction SilentlyContinue
} catch {}

Write-Host "Step 3: Creating Index Template for Strict Mapping..."
$template = @{
    index_patterns = @("logstash-*")
    template = @{
        mappings = @{
            properties = @{
                extra = @{
                    properties = @{
                        age = @{ 
                            type = "integer" 
                            ignore_malformed = $false
                        }
                    }
                }
            }
        }
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method Put -Uri "http://localhost:9200/_index_template/logstash_strict_mapping" -Body $template -ContentType "application/json"

Write-Host "Step 4: Starting Logstash..."
docker compose start logstash
# Wait for Logstash
$retries = 0
while ($retries -lt 60) {
    Start-Sleep -Seconds 2
    if (Test-NetConnection -ComputerName localhost -Port 8080 -InformationLevel Quiet) {
        Write-Host "Logstash is up."
        break
    }
    $retries++
}

Write-Host "Step 5: Sending 50 bad documents..."
$payload = @{message="dlq test"; extra=@{age="not_a_number"}} | ConvertTo-Json
for ($i=1; $i -le 50; $i++) {
    try {
        $null = Invoke-RestMethod -Method Post -Uri "http://localhost:8000/log" -Body $payload -ContentType "application/json"
    } catch {}
}

Write-Host "Step 6: Checking DLQ stats via API..."
Start-Sleep -Seconds 5
try {
    $stats = Invoke-RestMethod -Uri "http://localhost:9600/_node/stats/pipelines/main"
    $size = $stats.pipelines.main.dead_letter_queue.queue_size_in_bytes
    Write-Host "DLQ Size: $size bytes"
    
    if ($size -le 1) {
        Write-Host "WARNING: DLQ size is small ($size). Event might not have been rejected."
    }
} catch {
    Write-Host "Failed to get stats: $_"
}

Write-Host "Step 7: Restarting Logstash..."
docker compose restart logstash
Start-Sleep -Seconds 15

Write-Host "Step 8: Verifying DLQ persistence (stats)..."
try {
    # Wait for LS to come up
    Start-Sleep -Seconds 10
    $stats = Invoke-RestMethod -Uri "http://localhost:9600/_node/stats/pipelines/main"
    $newSize = $stats.pipelines.main.dead_letter_queue.queue_size_in_bytes
    Write-Host "DLQ Size after restart: $newSize bytes"
    
    if ($newSize -eq $size -and $size -gt 1) {
        Write-Host "SUCCESS: DLQ persisted ($size bytes)."
    } elseif ($newSize -gt 1) {
         Write-Host "SUCCESS: DLQ persisted (size: $newSize)."
    } else {
        Write-Host "FAILED: DLQ Empty or not persisted."
    }
} catch {
    Write-Host "Failed to get stats after restart: $_"
}

