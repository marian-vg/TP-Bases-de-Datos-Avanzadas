from pydantic import BaseModel


class CatastropheRequest(BaseModel):
    zoneId: int
    catastropheType: str
