import uuid
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError


def make_error(code: str, message: str, details: dict = None) -> dict:
    return {
        "error": {
            "code": code,
            "message": message,
            "details": details or {},
            "requestId": f"req_{uuid.uuid4().hex[:12]}",
        }
    }


def make_response(data: dict = None, meta: dict = None) -> dict:
    return {
        "data": data or {},
        "meta": meta or {},
    }


class AppError(HTTPException):
    def __init__(self, status_code: int, code: str, message: str, details: dict = None):
        super().__init__(status_code=status_code, detail=make_error(code, message, details))


async def validation_exception_handler(request: Request, exc: RequestValidationError):
    details = {}
    for err in exc.errors():
        loc = ".".join(str(p) for p in err["loc"])
        details[loc] = err["msg"]
    return JSONResponse(
        status_code=422,
        content=make_error("VALIDATION_ERROR", "Datos inválidos", details),
    )
