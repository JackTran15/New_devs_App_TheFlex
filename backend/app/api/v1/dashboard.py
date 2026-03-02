from fastapi import APIRouter, Depends, HTTPException
from typing import Dict, Any
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from app.services.cache import get_revenue_summary
from app.core.auth import authenticate_request as get_current_user

router = APIRouter()

@router.get("/dashboard/summary")
async def get_dashboard_summary(
    property_id: str,
    current_user: dict = Depends(get_current_user)
) -> Dict[str, Any]:
    tenant_id = getattr(current_user, "tenant_id", None)
    if tenant_id is None and isinstance(current_user, dict):
        tenant_id = current_user.get("tenant_id")
    if not tenant_id:
        raise HTTPException(status_code=401, detail="Missing tenant context")

    revenue_data = await get_revenue_summary(property_id, tenant_id)
    try:
        total_revenue = Decimal(str(revenue_data["total"])).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
    except (InvalidOperation, KeyError, TypeError):
        raise HTTPException(status_code=500, detail="Invalid revenue total format")
    
    return {
        "property_id": revenue_data['property_id'],
        "total_revenue": str(total_revenue),
        "currency": revenue_data['currency'],
        "reservations_count": revenue_data['count']
    }
