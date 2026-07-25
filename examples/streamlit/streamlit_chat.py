import json

import requests
import streamlit as st


RTL_CSS = """
<style>
:root, body, .stApp, [data-testid="stSidebar"], [data-testid="stChatMessage"] {
    direction: rtl;
    font-family: 'Noto Naskh Arabic', 'Noto Sans Arabic', 'Amiri', Tahoma, Arial, sans-serif;
}
.stApp *, [data-testid="stSidebar"] * {
    letter-spacing: 0 !important;
}
[data-testid="stChatMessageContent"], .stMarkdown, textarea, input {
    direction: rtl;
    unicode-bidi: plaintext;
    text-align: right;
}
code, pre, .stCodeBlock, .stCodeBlock * {
    direction: ltr !important;
    text-align: left !important;
    unicode-bidi: embed;
    font-family: 'Cascadia Code', 'Fira Code', monospace !important;
}
</style>
"""

DEFAULT_FUNCTION_PROPERTIES = """
{
    "type": "object",
    "properties": {
        "location": {
            "type": "string",
            "description": "The city and state, e.g. San Francisco, CA"
        }
    },
    "required": ["location"]
}
""".strip()

st.set_page_config(page_title="واجهة Codex العربية", page_icon="💬", layout="wide")
st.markdown(RTL_CSS, unsafe_allow_html=True)

# Session state for chat
if "messages" not in st.session_state:
    st.session_state.messages = []

st.title("💬 واجهة Codex العربية")

if "model" not in st.session_state:
    if "model" in st.query_params:
        st.session_state.model = st.query_params["model"]
    else:
        st.session_state.model = "small"

options = ["large", "small"]
selection = st.sidebar.segmented_control(
    "النموذج", options, selection_mode="single", default=st.session_state.model
)
# st.session_state.model = selection
st.query_params.update({"model": selection})

instructions = st.sidebar.text_area(
    "التعليمات",
    value="أنت مساعد مفيد يجيب عن الأسئلة ويساعد في تنفيذ المهام.",
)
effort = st.sidebar.radio(
    "مستوى الاستدلال",
    ["low", "medium", "high"],
    index=1,
)
st.sidebar.divider()
st.sidebar.subheader("الدوال")
use_functions = st.sidebar.toggle("استخدام الدوال", value=False)

st.sidebar.subheader("الأدوات المدمجة")
# Built-in Tools section
use_browser_search = st.sidebar.toggle("استخدام بحث المتصفح", value=False)
use_code_interpreter = st.sidebar.toggle("استخدام مفسر الشيفرة", value=False)

if use_functions:
    function_name = st.sidebar.text_input("اسم الدالة", value="get_weather")
    function_description = st.sidebar.text_area(
        "وصف الدالة", value="احصل على حالة الطقس لمدينة محددة"
    )
    function_parameters = st.sidebar.text_area(
        "معاملات الدالة", value=DEFAULT_FUNCTION_PROPERTIES
    )
else:
    function_name = None
    function_description = None
    function_parameters = None
st.sidebar.divider()
temperature = st.sidebar.slider(
    "درجة العشوائية", min_value=0.0, max_value=1.0, value=1.0, step=0.01
)
max_output_tokens = st.sidebar.slider(
    "الحد الأقصى لرموز الإخراج", min_value=1, max_value=131072, value=30000, step=1000
)
st.sidebar.divider()
debug_mode = st.sidebar.toggle("وضع التصحيح", value=False)

if debug_mode:
    st.sidebar.divider()
    st.sidebar.code(json.dumps(st.session_state.messages, indent=2), "json")

render_input = True

URL = (
    "http://localhost:8081/v1/responses"
    if selection == options[1]
    else "http://localhost:8000/v1/responses"
)


def trigger_fake_tool(container):
    function_output = st.session_state.get("function_output", "It's sunny!")
    last_call = st.session_state.messages[-1]
    if last_call.get("type") == "function_call":
        st.session_state.messages.append(
            {
                "type": "function_call_output",
                "call_id": last_call.get("call_id"),
                "output": function_output,
            }
        )
        run(container)


def run(container):
    tools = []
    if use_functions:
        tools.append(
            {
                "type": "function",
                "name": function_name,
                "description": function_description,
                "parameters": json.loads(function_parameters),
            }
        )
    # Add browser_search tool if checkbox is checked
    if use_browser_search:
        tools.append({"type": "browser_search"})
    if use_code_interpreter:
        tools.append({"type": "code_interpreter"})
    response = requests.post(
        URL,
        json={
            "input": st.session_state.messages,
            "stream": True,
            "instructions": instructions,
            "reasoning": {"effort": effort},
            "metadata": {"__debug": debug_mode},
            "tools": tools,
            "temperature": temperature,
            "max_output_tokens": max_output_tokens,
        },
        stream=True,
    )

    text_delta = ""
    code_interpreter_sessions: dict[str, dict] = {}

    _current_output_index = 0
    for line in response.iter_lines(decode_unicode=True):
        if not line or not line.startswith("data:"):
            continue
        data_str = line[len("data:") :].strip()
        if not data_str:
            continue
        try:
            data = json.loads(data_str)
        except Exception:
            continue

        event_type = data.get("type", "")
        output_index = data.get("output_index", 0)
        if event_type == "response.output_item.added":
            _current_output_index = output_index
            output_type = data.get("item", {}).get("type", "message")
            if output_type == "message":
                output = container.chat_message("assistant")
                placeholder = output.empty()
            elif output_type == "reasoning":
                output = container.chat_message("reasoning", avatar="🤔")
                placeholder = output.empty()
            elif output_type == "web_search_call":
                output = container.chat_message("web_search_call", avatar="🌐")
                output.code(
                    json.dumps(data.get("item", {}).get("action", {}), indent=4),
                    language="json",
                )
                placeholder = output.empty()
            elif output_type == "code_interpreter_call":
                item = data.get("item", {})
                item_id = item.get("id")
                message_container = container.chat_message(
                    "code_interpreter_call", avatar="🧪"
                )
                status_placeholder = message_container.empty()
                code_placeholder = message_container.empty()
                outputs_container = message_container.container()
                code_text = item.get("code") or ""
                if code_text:
                    code_placeholder.code(code_text, language="python")
                code_interpreter_sessions[item_id] = {
                    "status": status_placeholder,
                    "code": code_placeholder,
                    "outputs": outputs_container,
                    "code_text": code_text,
                    "rendered_outputs": False,
                }
                placeholder = status_placeholder
            text_delta = ""
        elif event_type == "response.reasoning_text.delta":
            output.avatar = "🤔"
            text_delta += data.get("delta", "")
            placeholder.markdown(text_delta)
        elif event_type == "response.output_text.delta":
            text_delta += data.get("delta", "")
            placeholder.markdown(text_delta)
        elif event_type == "response.output_item.done":
            item = data.get("item", {})
            if item.get("type") == "function_call":
                with container.chat_message("function_call", avatar="🔨"):
                    st.markdown(f"استدعاء `{item.get('name')}`")
                    st.caption("المعاملات")
                    st.code(item.get("arguments", ""), language="json")
            if item.get("type") == "web_search_call":
                placeholder.markdown("✅ اكتمل")
            if item.get("type") == "code_interpreter_call":
                item_id = item.get("id")
                session = code_interpreter_sessions.get(item_id)
                if session:
                    session["status"].markdown("✅ اكتمل")
                    final_code = item.get("code") or session["code_text"]
                    if final_code:
                        session["code"].code(final_code, language="python")
                        session["code_text"] = final_code
                    outputs = item.get("outputs") or []
                    if outputs and not session["rendered_outputs"]:
                        with session["outputs"]:
                            st.markdown("**المخرجات**")
                            for output_item in outputs:
                                output_type = output_item.get("type")
                                if output_type == "logs":
                                    st.code(
                                        output_item.get("logs", ""),
                                        language="text",
                                    )
                                elif output_type == "image":
                                    st.image(
                                        output_item.get("url", ""),
                                        caption="صورة مفسر الشيفرة",
                                    )
                        session["rendered_outputs"] = True
                    elif not outputs and not session["rendered_outputs"]:
                        with session["outputs"]:
                            st.caption("(لا توجد مخرجات)")
                        session["rendered_outputs"] = True
                else:
                    placeholder.markdown("✅ اكتمل")
        elif event_type == "response.code_interpreter_call.in_progress":
            item_id = data.get("item_id")
            session = code_interpreter_sessions.get(item_id)
            if session:
                session["status"].markdown("⏳ قيد التشغيل")
            else:
                try:
                    placeholder.markdown("⏳ قيد التشغيل")
                except Exception:
                    pass
        elif event_type == "response.code_interpreter_call.interpreting":
            item_id = data.get("item_id")
            session = code_interpreter_sessions.get(item_id)
            if session:
                session["status"].markdown("🧮 جارٍ التفسير")
        elif event_type == "response.code_interpreter_call.completed":
            item_id = data.get("item_id")
            session = code_interpreter_sessions.get(item_id)
            if session:
                session["status"].markdown("✅ اكتمل")
            else:
                try:
                    placeholder.markdown("✅ اكتمل")
                except Exception:
                    pass
        elif event_type == "response.code_interpreter_call_code.delta":
            item_id = data.get("item_id")
            session = code_interpreter_sessions.get(item_id)
            if session:
                session["code_text"] += data.get("delta", "")
                if session["code_text"].strip():
                    session["code"].code(session["code_text"], language="python")
        elif event_type == "response.code_interpreter_call_code.done":
            item_id = data.get("item_id")
            session = code_interpreter_sessions.get(item_id)
            if session:
                final_code = data.get("code") or session["code_text"]
                session["code_text"] = final_code
                if final_code:
                    session["code"].code(final_code, language="python")
        elif event_type == "response.completed":
            response = data.get("response", {})
            if debug_mode:
                container.expander("التصحيح", expanded=False).code(
                    response.get("metadata", {}).get("__debug", ""), language="text"
                )
            st.session_state.messages.extend(response.get("output", []))
            if st.session_state.messages[-1].get("type") == "function_call":
                with container.form("function_output_form"):
                    _function_output = st.text_input(
                        "أدخل ناتج الدالة",
                        value=st.session_state.get("function_output", "It's sunny!"),
                        key="function_output",
                    )
                    st.form_submit_button(
                        "إرسال ناتج الدالة",
                        on_click=trigger_fake_tool,
                        args=[container],
                    )
            # Optionally handle other event types...


# Chat display
for msg in st.session_state.messages:
    if msg.get("type") == "message":
        with st.chat_message(msg["role"]):
            for item in msg["content"]:
                if (
                    item.get("type") == "text"
                    or item.get("type") == "output_text"
                    or item.get("type") == "input_text"
                ):
                    st.markdown(item["text"])
                    if item.get("annotations"):
                        annotation_lines = "\n".join(
                            f"- {annotation.get('url')}"
                            for annotation in item["annotations"]
                            if annotation.get("url")
                        )
                        st.caption(f"**Annotations:**\n{annotation_lines}")
    elif msg.get("type") == "reasoning":
        with st.chat_message("reasoning", avatar="🤔"):
            for item in msg["content"]:
                if item.get("type") == "reasoning_text":
                    st.markdown(item["text"])
    elif msg.get("type") == "function_call":
        with st.chat_message("function_call", avatar="🔨"):
            st.markdown(f"استدعاء `{msg.get('name')}`")
            st.caption("المعاملات")
            st.code(msg.get("arguments", ""), language="json")
    elif msg.get("type") == "function_call_output":
        with st.chat_message("function_call_output", avatar="✅"):
            st.caption("الناتج")
            st.code(msg.get("output", ""), language="text")
    elif msg.get("type") == "web_search_call":
        with st.chat_message("web_search_call", avatar="🌐"):
            st.code(json.dumps(msg.get("action", {}), indent=4), language="json")
            st.markdown("✅ اكتمل")
    elif msg.get("type") == "code_interpreter_call":
        with st.chat_message("code_interpreter_call", avatar="🧪"):
            st.markdown("✅ اكتمل")

if render_input:
    # Input field
    if prompt := st.chat_input("اكتب رسالة..."):
        st.session_state.messages.append(
            {
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": prompt}],
            }
        )

        with st.chat_message("user"):
            st.markdown(prompt)

        run(st.container())
