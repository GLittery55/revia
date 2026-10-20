from __future__ import annotations

from copy import deepcopy
from pathlib import Path
from shutil import copy2

from docx import Document
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


REFERENCE = Path(
    "/Users/wj/Library/Containers/com.tencent.xinWeChat/Data/Documents/"
    "xwechat_files/wxid_1mnsbaymmelg11_d51d/msg/file/2026-08/问题.docx"
)
OUTPUT = Path(
    "/Users/wj/wj/chi27/BeyondComfort/output/docx/"
    "BeyondComfort_半结构化访谈提纲.docx"
)

BLUE = "0000FF"
RED = "FF0000"
BLACK = "000000"
GRAY = "666666"
LIGHT_BLUE = "DDEBF7"
# Use a macOS system font that is also visible to the headless LibreOffice
# renderer used for final visual QA. PingFang is not installed in this runtime.
FONT = "Hiragino Sans GB"


def set_run_font(run, size=10.5, color=BLACK, bold=False, italic=False, underline=False):
    run.font.name = FONT
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), FONT)
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), FONT)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), FONT)
    run.font.size = Pt(size)
    run.font.color.rgb = RGBColor.from_string(color)
    run.bold = bold
    run.italic = italic
    run.underline = underline
    return run


def shade_paragraph(paragraph, fill):
    p_pr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), fill)
    p_pr.append(shd)


def keep_with_next(paragraph):
    p_pr = paragraph._p.get_or_add_pPr()
    keep = OxmlElement("w:keepNext")
    p_pr.append(keep)


def clear_body(document):
    body = document._element.body
    sect_pr = body.sectPr
    for child in list(body):
        if child is not sect_pr:
            body.remove(child)


def add_text(document, text, *, color=BLACK, size=10.5, bold=False, italic=False,
             underline=False, before=0, after=4, left=0, first_line=None,
             alignment=None, keep=False):
    p = document.add_paragraph()
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.18
    p.paragraph_format.left_indent = Inches(left)
    if first_line is not None:
        p.paragraph_format.first_line_indent = Inches(first_line)
    if alignment is not None:
        p.alignment = alignment
    if keep:
        keep_with_next(p)
    set_run_font(p.add_run(text), size=size, color=color, bold=bold,
                 italic=italic, underline=underline)
    return p


def add_mixed(document, segments, *, before=0, after=4, left=0, size=10.5,
              alignment=None, keep=False, shade=None):
    p = document.add_paragraph()
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.18
    p.paragraph_format.left_indent = Inches(left)
    if alignment is not None:
        p.alignment = alignment
    if keep:
        keep_with_next(p)
    if shade:
        shade_paragraph(p, shade)
    for seg in segments:
        text = seg[0]
        opts = seg[1] if len(seg) > 1 else {}
        set_run_font(
            p.add_run(text),
            size=opts.get("size", size),
            color=opts.get("color", BLACK),
            bold=opts.get("bold", False),
            italic=opts.get("italic", False),
            underline=opts.get("underline", False),
        )
    return p


def add_section(document, title, time_hint):
    p = add_mixed(
        document,
        [
            (title, {"bold": True, "size": 13, "color": BLACK}),
            (f"  {time_hint}", {"size": 9.5, "color": GRAY, "italic": True}),
        ],
        before=12,
        after=6,
        keep=True,
        shade=LIGHT_BLUE,
    )
    p.paragraph_format.left_indent = Inches(0.05)
    return p


def add_question(document, number, question, probes, keywords=None, note=None):
    p = add_mixed(
        document,
        [
            (f"Q{number}. ", {"color": BLUE, "bold": True, "size": 11}),
            (question, {"color": BLUE, "bold": False, "size": 11}),
        ],
        before=7,
        after=3,
        keep=True,
    )
    if note:
        add_mixed(
            document,
            [
                ("访谈员提示：", {"bold": True, "color": BLACK}),
                (note, {"color": BLACK, "italic": True}),
            ],
            left=0.28,
            after=2,
        )
    for idx, probe in enumerate(probes, 1):
        add_mixed(
            document,
            [
                (f"可选追问{idx}：", {"bold": True, "color": BLACK}),
                (probe, {"color": BLACK}),
            ],
            left=0.28,
            after=2,
        )
    if keywords:
        add_mixed(
            document,
            [
                ("关注关键词：", {"bold": True, "color": BLACK}),
                ("、".join(keywords), {"color": RED, "bold": True}),
            ],
            left=0.28,
            after=5,
        )
    return p


def add_scale_probe(document, label, prompt, keywords):
    add_mixed(
        document,
        [
            (f"{label}：", {"bold": True, "color": BLACK}),
            (prompt, {"color": BLACK}),
        ],
        left=0.28,
        after=2,
    )
    add_mixed(
        document,
        [
            ("关注：", {"bold": True, "color": BLACK}),
            ("、".join(keywords), {"color": RED}),
        ],
        left=0.55,
        after=4,
    )


def build():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        OUTPUT.chmod(0o644)
    copy2(REFERENCE, OUTPUT)
    # The WeChat attachment is read-only; the working copy must be writable before saving.
    OUTPUT.chmod(0o644)
    document = Document(OUTPUT)
    clear_body(document)

    normal = document.styles["Normal"]
    normal.font.name = FONT
    normal._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), FONT)
    normal.font.size = Pt(10.5)
    normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
    normal.paragraph_format.space_after = Pt(4)

    for section in document.sections:
        section.left_margin = Inches(1.25)
        section.right_margin = Inches(1.25)
        section.top_margin = Inches(0.85)
        section.bottom_margin = Inches(0.85)

    title = add_text(
        document,
        "BeyondComfort 半结构化访谈提纲",
        size=18,
        bold=True,
        after=3,
        alignment=WD_ALIGN_PARAGRAPH.CENTER,
    )
    add_text(
        document,
        "适用于完成两种系统条件后的终访谈·建议时长45–60分钟",
        size=10,
        color=GRAY,
        after=10,
        alignment=WD_ALIGN_PARAGRAPH.CENTER,
    )

    add_mixed(
        document,
        [
            ("蓝色", {"color": BLUE, "bold": True}),
            ("为主问题；", {"color": BLACK}),
            ("黑色", {"color": BLACK, "bold": True}),
            ("为可选追问和访谈员提示；", {"color": BLACK}),
            ("红色", {"color": RED, "bold": True}),
            ("为需要注意捕捉的关键概念。不需要逐题追问，优先顺着参与者的叙述。", {"color": BLACK}),
        ],
        after=8,
        shade="F2F2F2",
    )

    add_section(document, "访谈前准备（仅访谈员可见）", "3–5分钟")
    prep_lines = [
        "参与者编号：____________________    条件顺序：____________________",
        "实际使用/完成次数：____________________    未完成阶段：____________________",
        "代表性会话及卡牌：________________________________________________",
        "是否展示过context/tracking cue：________________________________________",
        "问卷趋势：自我反思________  自我关怀________  自我批评/自我安抚________",
    ]
    for line in prep_lines:
        add_text(document, line, size=9.5, after=3)
    add_text(
        document,
        "注：问卷分数只用于选择追问，不用来告诉参与者“应该变好”。不直接追问涉及自伤的敏感单题；如参与者主动提及，按已审批的安全流程处理。",
        size=9.5,
        color=GRAY,
        italic=True,
        after=7,
    )

    add_section(document, "开场说明", "2分钟")
    add_text(
        document,
        "感谢你参加今天的访谈。我们想了解你使用两种反思系统时的真实体验。这不是对你反思得好不好的评价，也没有标准答案。我们尤其想知道哪些部分真正有帮助，哪些部分难以回答、显得重复或让你想停下。你可以跳过任何不想回答的问题。",
        after=5,
    )
    add_text(
        document,
        "如研究伦理方案包含录音：在开始前确认录音同意。",
        size=9.5,
        color=GRAY,
        italic=True,
        after=5,
    )

    add_section(document, "一、整体使用经验", "5–8分钟")
    add_question(
        document,
        1,
        "回顾这两周，你对整个使用经验有什么总体印象？",
        [
            "你最先想到的是哪一次对话或哪一个瞬间？",
            "哪些部分比你开始前预期的更好，哪些不如预期？",
        ],
        ["总体感受", "预期与实际", "印象深刻的时刻"],
    )
    add_question(
        document,
        2,
        "你通常在什么情况下打开系统，又是怎样决定聊哪件事的？",
        [
            "是事情刚发生时、情绪很强时，还是之后有空时使用？",
            "什么类型的事你愿意说，什么类型不愿意说？",
        ],
        ["使用情境", "披露边界", "使用动机"],
    )
    add_question(
        document,
        3,
        "有没有哪次对话你没有走完，或者中间就想停下？当时发生了什么？",
        [
            "是因为已经得到需要的帮助，还是时间、重复、难以回答、回复慢或技术问题？",
            "如果在后半段停下，是觉得反思已经够了，还是不知道怎样继续？",
        ],
        ["主动结束", "流程负担", "技术中断", "难回答"],
        note="不要把未达到completed直接表述为“失败”。",
    )

    add_section(document, "二、自我反思与理解", "8–10分钟")
    add_question(
        document,
        4,
        "选一次你印象比较深的对话，你开始时怎么理解那件事，对话后又怎么理解它？",
        [
            "有没有从一个比较笼统的感觉，走到更具体的事件、行为或影响？",
            "有没有什么是你自己在对话中第一次想到的？",
        ],
        ["反思深度", "具体化", "新的理解", "叙事变化"],
    )
    add_question(
        document,
        5,
        "系统在什么时候帮助你继续想下去，又在什么时候打断了你的思路？",
        [
            "有没有问题太抽象、太快下结论，或者反复追问已经说清的内容？",
            "你觉得最后的理解更像是你自己发现的，还是系统告诉你的？",
        ],
        ["反思支架", "过早解释", "重复追问", "用户主导"],
    )
    add_question(
        document,
        6,
        "两种系统在帮你理解自己这件事上，有什么不同？",
        [
            "哪一种更容易开始？哪一种更容易聊深？",
            "有没有一种更自然但比较浅，或更费力但带来了新角度？",
        ],
        ["条件差异", "易用性", "反思深度", "交互成本"],
        note="使用“第一种/第二种”或参与者自己的叫法，不告知哪一种是实验组。",
    )
    add_text(document, "可选：根据自我反思与洞察量表追问", bold=True, size=10, before=4, after=3)
    add_scale_probe(
        document,
        "如分数明显变化",
        "问卷中，你对“停下来反思、理解自己的想法是怎样产生的”的回答和开始时有些不同。这符合你的实际感受吗？有哪次对话可以说明？",
        ["符合/不符合", "具体例子", "变化来源"],
    )
    add_scale_probe(
        document,
        "如分数没有变化",
        "问卷中的反思与洞察回答前后比较接近。你觉得是实际确实没有变化，还是问卷没有捕捉到对话中发生的变化？",
        ["无变化", "量表敏感性", "短期与一般倾向"],
    )

    add_section(document, "三、自我关怀与坦诚面对", "8–10分钟")
    add_question(
        document,
        7,
        "在这些对话中，你对待自己的方式有没有发生什么变化？",
        [
            "当你觉得自己没做好时，系统的回应让你更容易理解自己，还是显得在安慰或开脱？",
            "有没有某句话让你觉得自己可以更公平地看这件事？",
        ],
        ["自我善待", "公平看待", "过度安慰", "开脱"],
    )
    add_question(
        document,
        8,
        "在同一件事里，你有没有同时看到：有些部分需要被理解，也有些部分需要自己面对、承担或改变？",
        [
            "可以分别说说是哪两个部分吗？",
            "系统有没有只顾着让你好受，或反过来只顾着让你改变？",
        ],
        ["理解困难", "现实影响", "责任", "改变", "compassionate candor"],
        note="不向参与者使用Tender/Fierce理论标签。",
    )
    add_question(
        document,
        9,
        "有没有某一次，系统的温和让你觉得自己被听见，或反而让你觉得事情被淡化了？",
        [
            "系统有没有否定你认为确实存在的行为或影响？",
            "有没有相反的情况：让你感到被评判、被教训或者被迫接受某个解释？",
        ],
        ["被理解", "淡化现实", "被评判", "过度温和"],
    )
    add_text(document, "可选：根据自我关怀量表追问", bold=True, size=10, before=4, after=3)
    add_scale_probe(
        document,
        "量表联动",
        "问卷中，你在遇到困难时关心、安抚或包容自己的回答前后有[上升/下降/基本不变]。你怎么理解这个结果？哪部分和系统有关，哪部分可能来自这一周的其他经历？",
        ["自我关怀", "归因谨慎", "系统外因素", "具体经历"],
    )

    add_section(document, "四、自我批评与解释权", "7–9分钟")
    add_question(
        document,
        10,
        "当你在对话中批评自己时，系统是怎样回应的？这种回应对你有什么影响？",
        [
            "它有没有帮你把“这次有些事没做好”和“我整个人都不行”区分开？",
            "这种区分对你有帮助，还是让你感到系统在反驳或纠正你？",
        ],
        ["具体行为", "整体人格否定", "羞耻", "自我安抚"],
    )
    add_question(
        document,
        11,
        "当系统对你的经历提出一种理解时，你觉得自己有多大空间去修改或拒绝它？",
        [
            "有没有你已经纠正了它，但后面它又重复了原来解释的情况？",
            "你觉得怎样的语气才能让一种候选理解更自然，不像在要求你确认“对不对”？",
        ],
        ["解释权", "拒绝", "修正", "错误前提重复", "自然承接"],
    )
    add_text(document, "可选：根据自我批评简表追问", bold=True, size=10, before=4, after=3)
    add_scale_probe(
        document,
        "量表联动",
        "问卷中，你对自己不足的批评、想要惩罚自己的倾向，或安抚自己的能力前后有[上升/下降/基本不变]。这符合你的体验吗？你会用哪次对话来说明？",
        ["不足自我", "厌恶自我", "安抚自我", "量表与经验一致性"],
    )

    add_section(document, "五、卡牌使用体验", "12–15分钟")
    add_question(
        document,
        12,
        "回想一张你印象最深的反思卡，你当时第一眼看到了什么，又是怎样开始解释它的？",
        [
            "画面是否足够具体，让你知道可以从哪里开始？",
            "它是否又足够开放，可以有不止一种说法？",
        ],
        ["可描述性", "暧昧度", "开放性", "第一印象"],
    )
    add_question(
        document,
        13,
        "你是怎样从卡牌画面中的人物、动作或关系，走到自己的现实经历的？",
        [
            "这个联系是你自己想到的，还是系统给出的？",
            "如果第一次联想不到，系统的提示是否有帮助？有没有提示已经替你解释了画面？",
        ],
        ["图像—现实连接", "用户自建联系", "scaffold", "过度解释"],
    )
    add_question(
        document,
        14,
        "卡牌有没有带来一种你原本没有想到、但又和自己有关的角度？",
        [
            "这种“意外但有关”的感觉是怎样产生的？",
            "有没有卡牌只是让流程更长、更费力，却没有带来新理解？",
        ],
        ["serendipity", "新角度", "投射距离", "额外负担"],
    )
    add_question(
        document,
        15,
        "在你已经把画面和经历连在一起后，系统后面怎样使用了这个联系？",
        [
            "它有没有继续基于你对卡牌的说法，还是换成了系统自己的牌义？",
            "当你不同意它的卡牌解读时，后面的对话有没有真正改变？",
        ],
        ["用户解释权", "卡牌固定含义", "接受/修正/拒绝", "后续约束"],
    )
    add_question(
        document,
        16,
        "和没有卡牌的那种对话相比，卡牌改变了什么？",
        [
            "哪一种更容易表达？哪一种更容易获得新角度？",
            "你会在什么情况下选择卡牌，什么情况下更想直接聊？",
        ],
        ["卡牌特异作用", "直接对话", "适用情境", "使用偏好"],
    )

    add_section(document, "六、情境数据（条件性追问）", "3–5分钟")
    add_question(
        document,
        17,
        "如果系统在对话中提到过你的休息、日程或其他记录，你当时怎么理解它的作用？",
        [
            "这条信息和你正在谈的事有关吗？它带来了现实锚点，还是只是重复一个事实？",
            "系统有没有把数据说成你为什么会这样的确定原因？",
            "你对数据的透明度、隐私和修正权有什么期望？",
        ],
        ["contextual cue", "相关性", "现实锚点", "因果过度", "隐私"],
        note="只在日志显示本人实际被展示过context cue时追问。",
    )

    add_section(document, "七、交互质量、行动与持续使用", "7–9分钟")
    add_question(
        document,
        18,
        "从对话节奏来看，什么时候像在和一个人自然地聊，什么时候像在走固定流程？",
        [
            "有没有反复出现相似开头、重复总结或“这个理解准确吗”之类的核对？",
            "等待时间、技术中断或抽卡失败是怎样影响你继续反思的？",
        ],
        ["自然对话", "模板感", "重复", "等待时间", "技术中断"],
    )
    add_question(
        document,
        19,
        "结束一次反思后，你对自己接下来要做什么，有没有变得更清楚？",
        [
            "系统提出的小步行动是否具体、可行，并且来自前面的反思？",
            "你后来真的做了吗？如果没做，是什么让它没有发生？",
        ],
        ["readiness to act", "小步行动", "可行性", "实际采纳"],
    )
    add_question(
        document,
        20,
        "实验结束后，你会在什么情况下继续使用这个系统？又有什么会让你不再使用？",
        [
            "如果只能保留一个功能，你会保留什么？",
            "如果只能修改一件事，你会修改什么？",
        ],
        ["持续使用", "价值时刻", "使用阻力", "改进优先级"],
    )

    add_section(document, "结束", "2分钟")
    add_question(
        document,
        21,
        "有没有什么是我们没有问到，但你觉得对理解这个系统很重要的？",
        ["如果让你给这个系统的设计者留一句话，你会说什么？"],
        ["未覆盖经验", "最终建议"],
    )

    add_text(
        document,
        "访谈员收尾：感谢参与者的具体反馈；提醒其后续数据处理与联系方式，不在现场解释或辩护系统设计。",
        size=9.5,
        color=GRAY,
        italic=True,
        before=6,
        after=3,
    )

    props = document.core_properties
    props.title = "BeyondComfort 半结构化访谈提纲"
    props.subject = "自我反思、自我关怀、自我批评与卡牌使用体验"
    props.author = "BeyondComfort Research Team"
    document.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build()
