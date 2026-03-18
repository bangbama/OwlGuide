from __future__ import annotations

import base64
import datetime
import json
import logging
import os
import re
import uuid
from typing import Any, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, Request, HTTPException
from google import genai
from google.cloud import firestore
from google.genai import types
from pydantic import BaseModel
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from starlette.status import HTTP_429_TOO_MANY_REQUESTS

# changed_in_version: 2026-03-15-1930

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# Version information (YYYY-MM-DD-HHMM format)
VERSION_TAG = "2026-03-15-1930"
PREVIOUS_VERSION = "2026-03-15-1904"

# Initialize FastAPI app
app = FastAPI(title="Owl Guide Backend", version=f"0.4.0-{VERSION_TAG}")

# ---------- 限流配置 ----------
# 限流key生成函数：IP + 设备ID
def get_ip_and_device_id(request: Request):
    ip = get_remote_address(request)
    device_id = request.headers.get("X-Device-ID", "unknown_device")
    return f"{ip}:{device_id}"

# 初始化限流器（内存存储，多实例部署可切换为Redis）
limiter = Limiter(key_func=get_ip_and_device_id)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# 自定义限流错误响应
@app.exception_handler(RateLimitExceeded)
async def custom_rate_limit_handler(request: Request, exc: RateLimitExceeded):
    retry_after = exc.detail.split(" ")[-1] if exc.detail else "60"
    raise HTTPException(
        status_code=HTTP_429_TOO_MANY_REQUESTS,
        detail={
            "code": 429,
            "message": "Too many requests. Please try again later.",
            "description": "Free limit: 10 requests per minute, 50 requests per day. You can use your own Gemini API Key for unlimited usage.",
            "retry_after": retry_after
        },
        headers={"Retry-After": retry_after}
    )

# Gemini configuration
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-pro")
USE_MOCK_ONLY = os.getenv("OWLGUIDE_USE_MOCK_ONLY", "false").lower() == "true"

# Initialize Gemini if API key is available
gemini_client = None
if GEMINI_API_KEY and not USE_MOCK_ONLY:
    try:
        gemini_client = genai.Client(api_key=GEMINI_API_KEY)
        logger.info("Gemini initialized successfully with model: %s", GEMINI_MODEL)
    except Exception as exc:
        logger.warning("Failed to initialize Gemini: %s. Will use mock mode.", exc)
        gemini_client = None

# Firestore configuration
FIRESTORE_ENABLED = os.getenv("OWLGUIDE_FIRESTORE_ENABLED", "true").lower() == "true"
GOOGLE_CLOUD_PROJECT = os.getenv("GOOGLE_CLOUD_PROJECT")
FIRESTORE_DATABASE = os.getenv("FIRESTORE_DATABASE", "(default)")

# Initialize Firestore client
firestore_client = None
if FIRESTORE_ENABLED and GOOGLE_CLOUD_PROJECT:
    try:
        firestore_client = firestore.Client(
            project=GOOGLE_CLOUD_PROJECT,
            database=FIRESTORE_DATABASE,
        )
        firestore_client.collection("sessions").limit(1).get()
        logger.info("Firestore initialized successfully")
    except Exception as exc:
        logger.warning("Failed to initialize Firestore: %s. Will skip persistence.", exc)
        firestore_client = None
else:
    if not FIRESTORE_ENABLED:
        logger.info("Firestore is disabled by configuration")
    elif not GOOGLE_CLOUD_PROJECT:
        logger.info("Firestore disabled: GOOGLE_CLOUD_PROJECT not set")


OWLGUIDE_SYSTEM_INSTRUCTION = """
You are Owl Guide, a patient and trustworthy digital assistant for older adults using macOS.

Core behavior:
- Answer the user's immediate question first when the screenshot makes the answer obvious.
- Use calm, concrete, plain language. No UI jargon like "element", "toggle", "container", or "pane".
- Give one safe next step, not a full procedure dump.
- Do not pretend a task is already finished unless the screenshot clearly confirms it.
- Prefer visible controls such as "Sign In", "New Message", "Send", "Search", or "术语库".
- Avoid vague targets like "screen_content", "main area", "current window", or "the interface".
- If the target is risky, state-changing, or uncertain, set requires_confirmation to true.
- The frontend can highlight, click, and type. Return action_plan items that help that frontend.
- If the screenshot is invalid or does not reveal a reliable target, degrade to safe text guidance instead of inventing one.

Your output must be valid JSON only.
""".strip()

ANALYSIS_TASK_TEMPLATE = """
Analyze this macOS screenshot and produce frontend-compatible guidance for Owl Guide.

Available request context:
- user_goal: {user_goal}
- app_name: {app_name}
- window_title: {window_title}
- screenshot_attached: {screenshot_attached}
- actionable_candidates_json: {actionable_candidates_json}
- readable_candidates_json: {readable_candidates_json}

What the frontend needs:
1. context: what the user is looking at right now, written concretely
2. likely_task: the most likely immediate task
3. safe_first_step: one specific safe next step
4. confirmation_question: a gentle yes/no follow-up
5. guide_card:
   - title: short, concrete, readable, no trailing punctuation
   - body: 1-2 short sentences, calm and specific
   - primary_action: same idea as safe_first_step, concise
6. action_plan:
   - prefer a first action that is useful to the current frontend: highlight, click, fill, fill_text, input, type, speak, instruction, or focus_suggestion
   - choose 2-3 actions max
   - use a concrete target label the user can actually see
   - if a provided candidate clearly matches the intended target, return its id in related_local_element
   - when the target is visible in the screenshot, return visual_bounding_box as [y_min, x_min, y_max, x_max] normalized to 0-1000
   - if typing is needed, include exact text in "value"
7. target_info:
   - kind: button, input, menu, link, checkbox, list_item, tab, or other concrete type
   - label: visible label
   - accessibility_label: accessibility-style label if inferable
   - local_candidate_id: best matching candidate id when one is available
   - visual_bounding_box: same normalized [y_min, x_min, y_max, x_max] box for the primary target when visible
   - rect: null unless you genuinely know exact coordinates
8. meta:
   - confidence: 0.0 to 1.0
   - risk_level: low, medium, or high
   - estimated_steps: rough estimate of remaining steps

Hard rules:
- Treat user_goal as the highest-priority signal. The screenshot and candidates must help answer that goal, not replace it.
- Decide from the user_goal and screenshot whether the user needs an explanation, a next step, or both.
- If the user asks an explanation question such as "what is this error", "why did this happen", "how do I fix this", "忘记用户名怎么办", or "能否用邮箱登录", answer that question first.
- Do not point to an unrelated button just because it is visually prominent.
- If no reliable UI action follows from the user's question, it is acceptable for action_plan to be instruction + speak only instead of forcing a click.
- Do not say "desktop interface", "generic area", "screen_content", or "review the current screen" unless there is truly no better evidence.
- If candidate ids are available, prefer picking a target from the provided candidates instead of inventing a new generic target.
- If you can see the target in the screenshot, return a tight visual_bounding_box. Do not omit it unless the target is genuinely unclear.
- If the screenshot suggests a login page, prefer targets like "Sign In", "Log In", "Continue", "Password", or "Email".
- If the screenshot suggests Mail composing, prefer targets like "Send", "To", "Subject", or "New Message".
- If the screenshot suggests 网易有道词典, prefer visible labels such as "术语库" when supported by the screenshot or request context.
- For risky actions such as payments, transfers, account deletion, password changes, or submission actions, be conservative and set requires_confirmation to true.
- Keep the wording elderly-friendly and readable.
""".strip()

LIGHTWEIGHT_ANALYSIS_TASK_TEMPLATE = """
Analyze this macOS screenshot and produce a smaller JSON answer for Owl Guide.

Available request context:
- user_goal: {user_goal}
- app_name: {app_name}
- window_title: {window_title}
- screenshot_attached: {screenshot_attached}
- actionable_candidates_json: {actionable_candidates_json}
- readable_candidates_json: {readable_candidates_json}

Return valid JSON only with these fields:
- context
- likely_task
- safe_first_step
- confirmation_question
- guide_card: title, body, primary_action
- action_plan: 1-2 items max
- target_info: optional
- meta: optional

Keep it simple:
- Prefer one concrete helpful target.
- If the user wants to search, type, or enter text, prefer the visible search or address field and include the exact value.
- If a provided candidate clearly matches, use its id in related_local_element.
- visual_bounding_box is optional in this lightweight mode, but include it when obvious.
- Do not force extra actions.
""".strip()

SUPPORTED_ACTION_TYPES = {
    "highlight",
    "click",
    "fill",
    "fill_text",
    "input",
    "type",
    "speak",
    "instruction",
    "focus_suggestion",
}
FILL_ACTION_TYPES = {"fill", "fill_text", "input", "type"}
GENERIC_TARGETS = {
    "",
    "screen_content",
    "main_area",
    "current_window",
    "current screen",
    "screen",
    "page",
    "content",
    "desktop interface",
    "interface",
    "window",
}
HIGH_RISK_TERMS = {
    "password",
    "passcode",
    "bank",
    "payment",
    "pay",
    "transfer",
    "wire",
    "delete",
    "remove",
    "purchase",
    "checkout",
    "social security",
    "ssn",
}


def get_current_utc_time() -> str:
    return datetime.datetime.utcnow().isoformat()


async def write_session(
    session_id: str,
    user_goal: str,
    app_name: Optional[str],
    window_title: Optional[str],
) -> None:
    if not firestore_client:
        return

    try:
        session_ref = firestore_client.collection("sessions").document(session_id)
        session_doc = session_ref.get()
        current_time = get_current_utc_time()
        session_data = {
            "session_id": session_id,
            "last_seen_at": current_time,
            "last_user_goal": user_goal,
            "last_app_name": app_name,
            "last_window_title": window_title,
        }

        if session_doc.exists:
            session_ref.update(session_data)
        else:
            session_data["created_at"] = current_time
            session_ref.set(session_data)
    except Exception as exc:
        logger.error("Failed to write session: %s", exc)


async def write_event(session_id: str, event_type: str, detail: dict) -> None:
    if not firestore_client:
        return

    try:
        event_id = str(uuid.uuid4())
        event_ref = (
            firestore_client.collection("sessions")
            .document(session_id)
            .collection("events")
            .document(event_id)
        )
        event_ref.set(
            {
                "type": event_type,
                "created_at": get_current_utc_time(),
                "session_id": session_id,
                "detail": detail,
            }
        )
    except Exception as exc:
        logger.error("Failed to write event: %s", exc)


class AnalyzeScreenRequest(BaseModel):
    session_id: str
    user_goal: str
    app_name: Optional[str] = None
    window_title: Optional[str] = None
    screenshot_base64: str
    actionable_candidates: list[dict[str, Any]] = []
    readable_candidates: list[dict[str, Any]] = []


class ActionPlanItem(BaseModel):
    type: str
    target: str
    text: str
    requires_confirmation: bool
    value: Optional[str] = None
    related_local_element: Optional[str] = None
    visual_bounding_box: Optional[list[int]] = None


class GuideCard(BaseModel):
    title: str
    body: str
    tone: str = "info"
    primary_action: str


class TargetInfo(BaseModel):
    kind: Optional[str] = None
    label: Optional[str] = None
    rect: Optional[dict] = None
    accessibility_label: Optional[str] = None
    local_candidate_id: Optional[str] = None
    visual_bounding_box: Optional[list[int]] = None


class MetaInfo(BaseModel):
    confidence: float = 0.8
    risk_level: str = "low"
    estimated_steps: int = 2


class AnalyzeScreenResponse(BaseModel):
    context: str
    likely_task: str
    safe_first_step: str
    confirmation_question: str
    action_plan: list[ActionPlanItem]
    guide_card: Optional[GuideCard] = None
    target_info: Optional[TargetInfo] = None
    meta: Optional[MetaInfo] = None


AnalyzeScreenRequest.model_rebuild()
ActionPlanItem.model_rebuild()
GuideCard.model_rebuild()
TargetInfo.model_rebuild()
MetaInfo.model_rebuild()
AnalyzeScreenResponse.model_rebuild()


def clean_text(value: Optional[str], fallback: str = "") -> str:
    if not value:
        return fallback
    return " ".join(str(value).strip().split())


def extract_goal_keywords(value: str) -> list[str]:
    normalized = clean_text(value).lower()
    english_tokens = re.findall(r"[a-z0-9_+-]{3,}", normalized)
    chinese_tokens = re.findall(r"[\u4e00-\u9fff]{2,}", normalized)
    keywords = [token for token in english_tokens + chinese_tokens if token not in {"help", "with", "this", "that"}]
    return list(dict.fromkeys(keywords))


def normalize_visual_bounding_box(value: Any) -> Optional[list[int]]:
    if not isinstance(value, list) or len(value) != 4:
        return None

    normalized: list[int] = []
    for component in value:
        try:
            number = int(round(float(component)))
        except (TypeError, ValueError):
            return None
        normalized.append(max(0, min(1000, number)))

    y_min, x_min, y_max, x_max = normalized
    if y_max <= y_min or x_max <= x_min:
        return None
    return normalized


def summarize_candidates(candidates: list[dict[str, Any]], limit: int = 8) -> list[dict[str, Any]]:
    summarized: list[dict[str, Any]] = []
    for candidate in candidates[:limit]:
        if not isinstance(candidate, dict):
            continue
        summarized.append(
            {
                "id": clean_text(candidate.get("id")),
                "rank": candidate.get("rank"),
                "label": clean_text(candidate.get("label")),
                "semantic_hint": clean_text(candidate.get("semanticHint") or candidate.get("semantic_hint")),
                "role": clean_text(candidate.get("role")),
                "subrole": clean_text(candidate.get("subrole")) or None,
            }
        )
    return summarized


def normalize_candidate_label(value: str) -> str:
    return clean_text(value).lower()


def choose_candidate_match(
    request: AnalyzeScreenRequest,
    requested_label: Optional[str] = None
) -> Optional[dict[str, Any]]:
    all_candidates = request.actionable_candidates + request.readable_candidates
    if not all_candidates:
        return None

    priorities = [
        clean_text(requested_label).lower(),
        clean_text(request.user_goal).lower(),
        clean_text(request.window_title).lower(),
    ]
    priorities.extend(extract_goal_keywords(request.user_goal))

    def score(candidate: dict[str, Any]) -> int:
        label = normalize_candidate_label(candidate.get("label", ""))
        semantic_hint = normalize_candidate_label(candidate.get("semanticHint") or candidate.get("semantic_hint") or "")
        role = normalize_candidate_label(candidate.get("role", ""))
        text = " ".join([label, semantic_hint, role])
        total = 0
        for index, priority in enumerate(priorities):
            if not priority:
                continue
            weight = 120 - index * 20
            if label == priority:
                total += weight + 80
            elif priority in label or label in priority:
                total += weight + 40
            elif priority in text:
                total += weight
        rank = candidate.get("rank")
        if isinstance(rank, int):
            total += max(0, 20 - rank)
        score_value = candidate.get("score")
        if isinstance(score_value, int):
            total += min(score_value, 40)
        return total

    best = max(all_candidates, key=score)
    return best if score(best) > 0 else None


def strip_title_punctuation(value: str) -> str:
    return clean_text(value).rstrip("。.!?！？:：;； ")


def infer_risk_level(request: AnalyzeScreenRequest, candidate_text: str = "") -> str:
    haystack = " ".join(
        [
            clean_text(request.user_goal).lower(),
            clean_text(request.app_name).lower(),
            clean_text(request.window_title).lower(),
            clean_text(candidate_text).lower(),
        ]
    )
    return "high" if any(term in haystack for term in HIGH_RISK_TERMS) else "low"


def requires_confirmation_by_default(request: AnalyzeScreenRequest, candidate_text: str = "") -> bool:
    return infer_risk_level(request, candidate_text) != "low"


def fallback_title(request: AnalyzeScreenRequest) -> str:
    title = strip_title_punctuation(clean_text(request.user_goal))
    return title or "Try asking Owl Guide again"


def decode_screenshot(request: AnalyzeScreenRequest) -> tuple[Optional[bytes], Optional[str], str]:
    raw = clean_text(request.screenshot_base64)
    if not raw:
        return None, None, "empty"

    payload = raw.split(",", 1)[1] if raw.startswith("data:") and "," in raw else raw
    try:
        image_bytes = base64.b64decode(payload, validate=False)
    except Exception:
        return None, None, "invalid_base64"

    if len(image_bytes) < 1024:
        return None, None, "too_small"

    if image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return image_bytes, "image/png", "ok"
    if image_bytes[:3] == b"\xff\xd8\xff":
        return image_bytes, "image/jpeg", "ok"
    if image_bytes.startswith(b"GIF87a") or image_bytes.startswith(b"GIF89a"):
        return image_bytes, "image/gif", "ok"
    if image_bytes.startswith(b"RIFF") and image_bytes[8:12] == b"WEBP":
        return image_bytes, "image/webp", "ok"
    return image_bytes, "image/png", "unknown_header"


def log_request_diagnostics(request: AnalyzeScreenRequest, screenshot_status: str, screenshot_size: int) -> None:
    diagnostics = {
        "session_id": request.session_id,
        "user_goal": clean_text(request.user_goal),
        "app_name": clean_text(request.app_name),
        "window_title": clean_text(request.window_title),
        "screenshot_status": screenshot_status,
        "screenshot_bytes": screenshot_size,
        "actionable_candidates": len(request.actionable_candidates),
        "readable_candidates": len(request.readable_candidates),
        "suspicious_goal": len(clean_text(request.user_goal)) < 5,
        "missing_app_name": not clean_text(request.app_name),
        "missing_window_title": not clean_text(request.window_title),
    }
    logger.info("[AnalyzeScreen][Request] %s", json.dumps(diagnostics, ensure_ascii=False))


def get_mock_response(request: AnalyzeScreenRequest, reason: str = "mock_fallback") -> AnalyzeScreenResponse:
    likely_task = clean_text(request.user_goal, "Try asking Owl Guide again")
    risk_level = infer_risk_level(request, likely_task)
    context = "Owl Guide did not get a reliable answer from this screen yet."
    safe_first_step = "Please try again, or ask a shorter and more specific question."
    return AnalyzeScreenResponse(
        context=context,
        likely_task=likely_task,
        safe_first_step=safe_first_step,
        confirmation_question="Would you like to try again with a clearer question?",
        action_plan=[
            ActionPlanItem(
                type="instruction",
                target="user",
                text=safe_first_step,
                requires_confirmation=False,
                related_local_element=None,
                visual_bounding_box=None,
            ),
            ActionPlanItem(
                type="speak",
                target="user",
                text=f"{context} ({reason})",
                requires_confirmation=False,
                related_local_element=None,
                visual_bounding_box=None,
            ),
        ],
        guide_card=GuideCard(
            title=fallback_title(request),
            body=context,
            tone="warning",
            primary_action=safe_first_step,
        ),
        target_info=None,
        meta=MetaInfo(
            confidence=0.55,
            risk_level=risk_level,
            estimated_steps=2,
        ),
    )


def build_prompt(request: AnalyzeScreenRequest, screenshot_available: bool) -> str:
    return ANALYSIS_TASK_TEMPLATE.format(
        user_goal=clean_text(request.user_goal, "Help me continue safely"),
        app_name=clean_text(request.app_name, "Unknown app"),
        window_title=clean_text(request.window_title, "Unknown window"),
        screenshot_attached="yes" if screenshot_available else "no",
        actionable_candidates_json=json.dumps(summarize_candidates(request.actionable_candidates), ensure_ascii=False),
        readable_candidates_json=json.dumps(summarize_candidates(request.readable_candidates), ensure_ascii=False),
    )


def build_lightweight_prompt(request: AnalyzeScreenRequest, screenshot_available: bool) -> str:
    return LIGHTWEIGHT_ANALYSIS_TASK_TEMPLATE.format(
        user_goal=clean_text(request.user_goal, "Help me continue safely"),
        app_name=clean_text(request.app_name, "Unknown app"),
        window_title=clean_text(request.window_title, "Unknown window"),
        screenshot_attached="yes" if screenshot_available else "no",
        actionable_candidates_json=json.dumps(summarize_candidates(request.actionable_candidates), ensure_ascii=False),
        readable_candidates_json=json.dumps(summarize_candidates(request.readable_candidates), ensure_ascii=False),
    )


def sanitize_action_type(raw_type: Any) -> str:
    action_type = clean_text(str(raw_type or "instruction")).lower()
    if action_type not in SUPPORTED_ACTION_TYPES:
        return "instruction"
    return action_type


def choose_target_label(raw_response: dict[str, Any], request: AnalyzeScreenRequest) -> str:
    target_info = raw_response.get("target_info") if isinstance(raw_response.get("target_info"), dict) else {}
    preferred = [
        clean_text(target_info.get("label")),
        clean_text(target_info.get("accessibility_label")),
    ]
    for action in raw_response.get("action_plan", []):
        if isinstance(action, dict):
            preferred.append(clean_text(action.get("target")))
    candidate_match = choose_candidate_match(request)
    if candidate_match:
        preferred.append(clean_text(candidate_match.get("label")))

    for candidate in preferred:
        if candidate and candidate.lower() not in GENERIC_TARGETS:
            return candidate
    return ""


def extract_json_object(payload: str) -> Optional[dict[str, Any]]:
    text = clean_text(payload)
    if not text:
        return None
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else None
    except Exception:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end <= start:
        return None
    try:
        parsed = json.loads(text[start:end + 1])
        return parsed if isinstance(parsed, dict) else None
    except Exception:
        return None


def coerce_raw_response(raw_response: Any) -> Optional[dict[str, Any]]:
    if raw_response is None:
        return None
    if isinstance(raw_response, dict):
        return raw_response
    if isinstance(raw_response, BaseModel):
        data = raw_response.model_dump()
        return data if isinstance(data, dict) else None
    if isinstance(raw_response, list):
        for item in raw_response:
            coerced = coerce_raw_response(item)
            if coerced:
                return coerced
        return None
    if isinstance(raw_response, str):
        return extract_json_object(raw_response)
    if hasattr(raw_response, "model_dump"):
        try:
            data = raw_response.model_dump()
            return data if isinstance(data, dict) else None
        except Exception:
            return None
    if hasattr(raw_response, "__dict__"):
        data = getattr(raw_response, "__dict__", None)
        return data if isinstance(data, dict) else None
    return None


def normalize_response(raw_response: dict[str, Any], request: AnalyzeScreenRequest) -> AnalyzeScreenResponse:
    try:
        if not isinstance(raw_response, dict):
            logger.warning("Invalid response type: %s. Using mock fallback.", type(raw_response))
            return get_mock_response(request, reason="invalid_response_type")

        chosen_target = choose_target_label(raw_response, request)
        candidate_match = choose_candidate_match(request, requested_label=chosen_target)
        target_kind = clean_text((candidate_match or {}).get("role")) or "other"
        default_ax_label = clean_text((candidate_match or {}).get("label")) or chosen_target
        risk_level = raw_response.get("meta", {}).get("risk_level") if isinstance(raw_response.get("meta"), dict) else None
        risk_level = risk_level if risk_level in {"low", "medium", "high"} else infer_risk_level(request, chosen_target)

        context = clean_text(
            raw_response.get("context"),
            f"You are in {clean_text(request.app_name, 'this app')}.",
        )
        likely_task = clean_text(
            raw_response.get("likely_task"),
            clean_text(request.user_goal, "Continue safely with the current task"),
        )
        safe_first_step = clean_text(
            raw_response.get("safe_first_step"),
            f"Select {chosen_target}.",
        )
        confirmation_question = clean_text(
            raw_response.get("confirmation_question"),
            "Would you like me to guide you one step at a time?",
        )
        raw_target_info = raw_response.get("target_info") if isinstance(raw_response.get("target_info"), dict) else {}

        normalized_target_box = normalize_visual_bounding_box(raw_target_info.get("visual_bounding_box"))
        normalized_actions: list[ActionPlanItem] = []
        for raw_action in raw_response.get("action_plan", [])[:3]:
            if not isinstance(raw_action, dict):
                continue
            action_type = sanitize_action_type(raw_action.get("type"))
            action_target = clean_text(raw_action.get("target"), chosen_target)
            if action_target.lower() in GENERIC_TARGETS and chosen_target:
                action_target = chosen_target
            action_text = clean_text(raw_action.get("text"), safe_first_step)
            requires_confirmation = bool(
                raw_action.get("requires_confirmation", requires_confirmation_by_default(request, action_text))
            )
            value = clean_text(raw_action.get("value"))
            fallback_candidate = choose_candidate_match(request, requested_label=action_target or chosen_target)
            related_local_element = clean_text(raw_action.get("related_local_element")) or clean_text(
                fallback_candidate.get("id") if fallback_candidate else ""
            )
            visual_bounding_box = normalize_visual_bounding_box(raw_action.get("visual_bounding_box")) or normalized_target_box

            if action_type in FILL_ACTION_TYPES and not value:
                action_type = "instruction"

            normalized_actions.append(
                ActionPlanItem(
                    type=action_type,
                    target=action_target,
                    text=action_text,
                    requires_confirmation=requires_confirmation,
                    value=value or None,
                    related_local_element=related_local_element or None,
                    visual_bounding_box=visual_bounding_box,
                )
            )

        if not normalized_actions:
            normalized_actions.append(
                ActionPlanItem(
                    type="highlight",
                    target=chosen_target or "user",
                    text=safe_first_step,
                    requires_confirmation=False,
                    related_local_element=clean_text(raw_target_info.get("local_candidate_id")) or None,
                    visual_bounding_box=normalized_target_box,
                )
            )
        if len(normalized_actions) == 1:
            normalized_actions.append(
                ActionPlanItem(
                    type="speak",
                    target="user",
                    text=safe_first_step,
                    requires_confirmation=False,
                    related_local_element=None,
                    visual_bounding_box=None,
                )
            )

        raw_guide_card = raw_response.get("guide_card") if isinstance(raw_response.get("guide_card"), dict) else {}
        guide_card = GuideCard(
            title=strip_title_punctuation(
                clean_text(raw_guide_card.get("title"), likely_task or chosen_target)
            ),
            body=clean_text(raw_guide_card.get("body"), context),
            tone=clean_text(raw_guide_card.get("tone"), "warning" if risk_level == "high" else "info"),
            primary_action=clean_text(raw_guide_card.get("primary_action"), safe_first_step),
        )

        target_info = TargetInfo(
            kind=clean_text(raw_target_info.get("kind"), target_kind) or None,
            label=clean_text(raw_target_info.get("label"), chosen_target) or None,
            rect=raw_target_info.get("rect") if isinstance(raw_target_info.get("rect"), dict) else None,
            accessibility_label=clean_text(
                raw_target_info.get("accessibility_label"),
                default_ax_label or chosen_target,
            )
            or None,
            local_candidate_id=clean_text(raw_target_info.get("local_candidate_id"))
            or clean_text((choose_candidate_match(request, requested_label=chosen_target) or {}).get("id"))
            or None,
            visual_bounding_box=normalized_target_box
            or next((action.visual_bounding_box for action in normalized_actions if action.visual_bounding_box), None),
        )

        raw_meta = raw_response.get("meta") if isinstance(raw_response.get("meta"), dict) else {}
        meta = MetaInfo(
            confidence=max(0.0, min(1.0, float(raw_meta.get("confidence", 0.82)))),
            risk_level=risk_level,
            estimated_steps=max(1, int(raw_meta.get("estimated_steps", 2))),
        )

        normalized = AnalyzeScreenResponse(
            context=context,
            likely_task=likely_task,
            safe_first_step=safe_first_step,
            confirmation_question=confirmation_question,
            action_plan=normalized_actions,
            guide_card=guide_card,
            target_info=target_info,
            meta=meta,
        )
        logger.info("[AnalyzeScreen][Normalized] %s", normalized.model_dump_json())
        return normalized
    except Exception as exc:
        logger.error("Failed to normalize response: %s", exc)
        return get_mock_response(request, reason="normalize_failure")


RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "context": {"type": "string"},
        "likely_task": {"type": "string"},
        "safe_first_step": {"type": "string"},
        "confirmation_question": {"type": "string"},
        "action_plan": {
            "type": "array",
            "minItems": 2,
            "maxItems": 3,
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "enum": sorted(SUPPORTED_ACTION_TYPES),
                    },
                    "target": {"type": "string"},
                    "text": {"type": "string"},
                    "requires_confirmation": {"type": "boolean"},
                    "value": {"type": "string"},
                    "related_local_element": {"type": "string"},
                    "visual_bounding_box": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "minItems": 4,
                        "maxItems": 4,
                    },
                },
                "required": ["type", "target", "text", "requires_confirmation"],
            },
        },
        "guide_card": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string"},
                "tone": {"type": "string"},
                "primary_action": {"type": "string"},
            },
            "required": ["title", "body", "primary_action"],
        },
        "target_info": {
            "type": "object",
            "properties": {
                "kind": {"type": "string"},
                "label": {"type": "string"},
                "rect": {"type": "object"},
                "accessibility_label": {"type": "string"},
                "local_candidate_id": {"type": "string"},
                "visual_bounding_box": {
                    "type": "array",
                    "items": {"type": "integer"},
                    "minItems": 4,
                    "maxItems": 4,
                },
            },
        },
        "meta": {
            "type": "object",
            "properties": {
                "confidence": {"type": "number"},
                "risk_level": {"type": "string", "enum": ["low", "medium", "high"]},
                "estimated_steps": {"type": "integer"},
            },
        },
    },
    "required": [
        "context",
        "likely_task",
        "safe_first_step",
        "confirmation_question",
        "action_plan",
    ],
}

LIGHTWEIGHT_RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "context": {"type": "string"},
        "likely_task": {"type": "string"},
        "safe_first_step": {"type": "string"},
        "confirmation_question": {"type": "string"},
        "action_plan": {
            "type": "array",
            "minItems": 1,
            "maxItems": 2,
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": sorted(SUPPORTED_ACTION_TYPES)},
                    "target": {"type": "string"},
                    "text": {"type": "string"},
                    "requires_confirmation": {"type": "boolean"},
                    "value": {"type": "string"},
                    "related_local_element": {"type": "string"},
                    "visual_bounding_box": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "minItems": 4,
                        "maxItems": 4,
                    },
                },
                "required": ["type", "text"],
            },
        },
        "guide_card": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string"},
                "primary_action": {"type": "string"},
            },
        },
        "target_info": {"type": "object"},
        "meta": {"type": "object"},
    },
    "required": ["context", "likely_task", "safe_first_step", "confirmation_question", "action_plan"],
}


async def call_gemini(request: AnalyzeScreenRequest) -> Optional[AnalyzeScreenResponse]:
    if not gemini_client:
        return None

    image_bytes, mime_type, screenshot_status = decode_screenshot(request)

    def make_parts(prompt_text: str) -> list[types.Part]:
        built_parts: list[types.Part] = [types.Part.from_text(text=prompt_text)]
        if image_bytes and mime_type:
            built_parts.append(types.Part.from_bytes(data=image_bytes, mime_type=mime_type))
        return built_parts

    def invoke(prompt_text: str, schema: dict[str, Any], max_output_tokens: int) -> Any:
        response = gemini_client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[types.Content(role="user", parts=make_parts(prompt_text))],
            config=types.GenerateContentConfig(
                temperature=0.15,
                top_p=0.85,
                max_output_tokens=max_output_tokens,
                response_mime_type="application/json",
                response_schema=schema,
                system_instruction=OWLGUIDE_SYSTEM_INSTRUCTION,
            ),
        )
        raw_response: Any = coerce_raw_response(response.parsed)
        if raw_response is None and getattr(response, "text", None):
            raw_response = extract_json_object(response.text)
        return raw_response

    try:
        prompt = build_prompt(request, screenshot_available=image_bytes is not None)
        raw_response = invoke(prompt, RESPONSE_SCHEMA, 1400)
        if raw_response is None:
            logger.warning("[AnalyzeScreen][GeminiRaw] full contract unusable, retrying lightweight contract")
            light_prompt = build_lightweight_prompt(request, screenshot_available=image_bytes is not None)
            raw_response = invoke(light_prompt, LIGHTWEIGHT_RESPONSE_SCHEMA, 900)
        logger.info(
            "[AnalyzeScreen][GeminiRaw] %s",
            json.dumps(raw_response, ensure_ascii=False),
        )
        return normalize_response(raw_response, request)
    except Exception as exc:
        logger.error("Gemini call failed: %s", exc)
        return None


@app.get("/health")
@app.get("/ping")
async def health():
    return {"ok": True}


@app.post("/analyze-screen", response_model=AnalyzeScreenResponse)
@limiter.limit("10/minute")
@limiter.limit("50/day")
async def analyze_screen(request: Request, analyze_request: AnalyzeScreenRequest):
    image_bytes, _, screenshot_status = decode_screenshot(analyze_request)
    log_request_diagnostics(analyze_request, screenshot_status, len(image_bytes or b""))
    response_source = "mock"

    try:
        await write_event(
            analyze_request.session_id,
            "analyze_requested",
            {
                "user_goal": analyze_request.user_goal,
                "app_name": analyze_request.app_name,
                "window_title": analyze_request.window_title,
                "screenshot_status": screenshot_status,
            },
        )
        await write_session(
            analyze_request.session_id,
            analyze_request.user_goal,
            analyze_request.app_name,
            analyze_request.window_title,
        )
    except Exception as exc:
        logger.error("Failed to write pre-request Firestore data: %s", exc)

    if USE_MOCK_ONLY:
        logger.info("Using mock mode (forced by OWLGUIDE_USE_MOCK_ONLY)")
        response = get_mock_response(analyze_request, reason="forced_mock_mode")
        response_source = "mock"
    elif gemini_client:
        gemini_response = await call_gemini(analyze_request)
        if gemini_response:
            logger.info("Successfully got response from Gemini")
            response = gemini_response
            response_source = "gemini"
        else:
            fallback_reason = "gemini_failed_text_only" if screenshot_status != "ok" else "gemini_failed"
            response = get_mock_response(analyze_request, reason=fallback_reason)
            response_source = "mock"
    else:
        response = get_mock_response(analyze_request, reason="gemini_unavailable")
        response_source = "mock"

    try:
        await write_event(
            analyze_request.session_id,
            "analyze_completed",
            {
                "result_status": "success",
                "response_source": response_source,
                "has_gemini_enabled": gemini_client is not None,
                "forced_mock_mode": USE_MOCK_ONLY,
                "screenshot_status": screenshot_status,
            },
        )
    except Exception as exc:
        logger.error("Failed to write completion Firestore data: %s", exc)

    return response


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
