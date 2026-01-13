import os
import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

LOGSTASH_URL = os.getenv("LOGSTASH_URL", "http://localhost:8080")

class LogMessage(BaseModel):
    message: str
    extra: dict = {}

@app.post("/log")
async def send_log(log: LogMessage):
    """
    Sends a log message to Logstash.
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                LOGSTASH_URL,
                json=log.model_dump(),
                timeout=5.0
            )
            response.raise_for_status()
            logger.info(f"Successfully sent log to Logstash: {response.status_code}")
            return {"status": "success", "logstash_response": response.status_code}
    except httpx.HTTPStatusError as e:
        logger.error(f"Logstash returned error: {e.response.status_code} - {e.response.text}")
        raise HTTPException(status_code=e.response.status_code, detail=f"Logstash error: {e.response.text}")
    except httpx.RequestError as e:
        logger.error(f"Failed to connect to Logstash: {e}")
        raise HTTPException(status_code=503, detail=f"Failed to connect to Logstash: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {"status": "ok"}
