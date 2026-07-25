import json
import requests
import gradio as gr

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

def chat_with_model(message, history, model_choice, instructions, effort, use_functions,
                   function_name, function_description, function_parameters,
                   use_browser_search, temperature, max_output_tokens, debug_mode):

    if not message.strip():
        return history, ""

    # Append user message and empty assistant placeholder (idiomatic Gradio pattern)
    history = history + [[message, ""]]

    # Build messages list from history (excluding the empty assistant placeholder)
    messages = []

    # Convert history to messages format (excluding the last empty assistant message)
    for user_msg, assistant_msg in history[:-1]:
        if user_msg:
            messages.append({
                "type": "message",
                "role": "user",
                "content": [{"type": "input_text", "text": user_msg}]
            })
        if assistant_msg:
            messages.append({
                "type": "message",
                "role": "assistant",
                "content": [{"type": "output_text", "text": assistant_msg}]
            })

    # Add current user message
    messages.append({
        "type": "message",
        "role": "user",
        "content": [{"type": "input_text", "text": message}]
    })

    # Prepare tools
    tools = []
    if use_functions:
        try:
            tools.append({
                "type": "function",
                "name": function_name,
                "description": function_description,
                "parameters": json.loads(function_parameters),
            })
        except json.JSONDecodeError:
            pass

    if use_browser_search:
        tools.append({"type": "browser_search"})

    # Get URL based on model (matching streamlit logic)
    options = ["large", "small"]
    URL = ("http://localhost:8081/v1/responses" if model_choice == options[1]
           else "http://localhost:8000/v1/responses")

    try:
        response = requests.post(
            URL,
            json={
                "input": messages,
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

        full_content = ""
        in_reasoning = False

        for line in response.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data:"):
                continue
            data_str = line[len("data:"):].strip()
            if not data_str:
                continue

            try:
                data = json.loads(data_str)
            except Exception:
                continue

            event_type = data.get("type", "")

            if event_type == "response.output_item.added":
                output_type = data.get("item", {}).get("type", "message")

                if output_type == "reasoning":
                    if not in_reasoning:
                        full_content += "🤔 **جارٍ التفكير...**\n"
                        in_reasoning = True
                elif output_type == "message":
                    if in_reasoning:
                        full_content += "\n\n"
                        in_reasoning = False

            elif event_type == "response.reasoning_text.delta":
                delta = data.get("delta", "")
                full_content += delta

                # Update last assistant message (idiomatic Gradio pattern)
                history[-1][1] = full_content
                yield history, ""

            elif event_type == "response.output_text.delta":
                delta = data.get("delta", "")
                full_content += delta

                # Update last assistant message (idiomatic Gradio pattern)
                history[-1][1] = full_content
                yield history, ""

            elif event_type == "response.output_item.done":
                item = data.get("item", {})
                if item.get("type") == "function_call":
                    function_call_text = f"\n\n🔨 استدعاء `{item.get('name')}`\n**المعاملات**\n```json\n{item.get('arguments', '')}\n```"
                    full_content += function_call_text

                    # Update last assistant message (idiomatic Gradio pattern)
                    history[-1][1] = full_content
                    yield history, ""

                elif item.get("type") == "web_search_call":
                    web_search_text = f"\n\n🌐 **بحث الويب**\n```json\n{json.dumps(item.get('action', {}), indent=2)}\n```\n✅ اكتمل"
                    full_content += web_search_text

                    # Update last assistant message (idiomatic Gradio pattern)
                    history[-1][1] = full_content
                    yield history, ""

            elif event_type == "response.completed":
                response_data = data.get("response", {})
                if debug_mode:
                    debug_info = response_data.get("metadata", {}).get("__debug", "")
                    if debug_info:
                        full_content += f"\n\n**التصحيح**\n```\n{debug_info}\n```"

                        # Update last assistant message (idiomatic Gradio pattern)
                        history[-1][1] = full_content
                        yield history, ""
                break

        # Return final history and empty string to clear textbox
        return history, ""

    except Exception as e:
        error_message = f"❌ خطأ: {str(e)}"
        history[-1][1] = error_message
        return history, ""


# Create the Gradio interface
with gr.Blocks(
    title="💬 واجهة Codex العربية",
    css="""
    :root { font-family: 'Noto Naskh Arabic', 'Noto Sans Arabic', 'Amiri', Tahoma, Arial, sans-serif; }
    .gradio-container, .gradio-container * {
        direction: rtl;
        unicode-bidi: plaintext;
        text-align: right;
        font-family: 'Noto Naskh Arabic', 'Noto Sans Arabic', 'Amiri', Tahoma, Arial, sans-serif !important;
        letter-spacing: 0;
    }
    textarea, input, .prose, .message, code, pre {
        unicode-bidi: plaintext;
    }
    code, pre { direction: ltr; text-align: left; font-family: 'Cascadia Code', 'Fira Code', monospace !important; }
    """,
) as demo:
    gr.Markdown("# 💬 واجهة Codex العربية")

    with gr.Row():
        with gr.Column(scale=3):
            chatbot = gr.Chatbot(height=500)

            with gr.Row():
                msg = gr.Textbox(placeholder="اكتب رسالة...", scale=4, show_label=False)
                send_btn = gr.Button("إرسال", scale=1)

            clear_btn = gr.Button("مسح المحادثة")

        with gr.Column(scale=1):
            model_choice = gr.Radio(["large", "small"], value="small", label="النموذج")

            instructions = gr.Textbox(
                label="التعليمات",
                value="أنت مساعد مفيد يجيب عن الأسئلة ويساعد في تنفيذ المهام.",
                lines=3
            )

            effort = gr.Radio(["low", "medium", "high"], value="medium", label="مستوى الاستدلال")

            gr.Markdown("#### الدوال")
            use_functions = gr.Checkbox(label="استخدام الدوال", value=False)

            with gr.Column(visible=False) as function_group:
                function_name = gr.Textbox(label="اسم الدالة", value="get_weather")
                function_description = gr.Textbox(
                    label="وصف الدالة",
                    value="احصل على حالة الطقس لمدينة محددة"
                )
                function_parameters = gr.Textbox(
                    label="معاملات الدالة",
                    value=DEFAULT_FUNCTION_PROPERTIES,
                    lines=6
                )

            # Conditional browser search (matching Streamlit logic)
            # In Streamlit: if "show_browser" in st.query_params:
            # For Gradio, we'll always show it (simplified)
            gr.Markdown("#### أدوات مدمجة")
            use_browser_search = gr.Checkbox(label="استخدام بحث المتصفح", value=False)

            temperature = gr.Slider(0.0, 1.0, value=1.0, step=0.01, label="درجة العشوائية")
            max_output_tokens = gr.Slider(1000, 20000, value=1024, step=100, label="الحد الأقصى لرموز الإخراج")

            debug_mode = gr.Checkbox(label="وضع التصحيح", value=False)

    # Event handlers
    def toggle_function_group(use_funcs):
        return gr.update(visible=use_funcs)

    use_functions.change(toggle_function_group, use_functions, function_group)

    # Chat functionality
    inputs = [msg, chatbot, model_choice, instructions, effort, use_functions,
              function_name, function_description, function_parameters,
              use_browser_search, temperature, max_output_tokens, debug_mode]

    msg.submit(chat_with_model, inputs, [chatbot, msg])
    send_btn.click(chat_with_model, inputs, [chatbot, msg])
    clear_btn.click(lambda: [], outputs=chatbot)


if __name__ == "__main__":
    demo.launch()
