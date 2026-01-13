$payload = @{message="load test"; extra=@{data="x" * 1000}} | ConvertTo-Json
$count = 0
$failed = $false

while (-not $failed) {
    $count++
    try {
        $response = Invoke-RestMethod -Method Post -Uri "http://localhost:8000/log" -Body $payload -ContentType "application/json" -ErrorAction Stop
        if ($count % 50 -eq 0) { Write-Host "Sent $count requests..." }
    } catch {
        Write-Host "Request $count failed!"
        Write-Host $_.Exception.Message
        if ($_.Exception.Response) {
            Write-Host "Status Code: $($_.Exception.Response.StatusCode.value__)"
            $failed = $true
        }
    }
    
    if ($count -gt 10000) {
        Write-Host "Sent 10000 requests without failure. Stopping."
        break
    }
}
