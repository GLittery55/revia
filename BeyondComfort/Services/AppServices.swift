import Foundation
import HealthKit
import EventKit

actor RemoteAPIService {
    static let shared = RemoteAPIService()

    private struct TurnCompletionResponse: Decodable {
        let content: String
    }

    private let session: URLSession
    private let baseURL: URL?

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
        let raw = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        baseURL = raw.isEmpty || raw.contains("$(") ? nil : URL(string: raw)
    }

    var isConfigured: Bool { baseURL != nil }

    func register(username: String, password: String) async throws -> AccountUser {
        try await request("/api/auth/register", method: "POST", body: ["username": username, "password": password, "consentAccepted": true])
    }

    func login(username: String, password: String) async throws -> AccountUser {
        try await request("/api/auth/login", method: "POST", body: ["username": username, "password": password])
    }

    func currentUser() async throws -> AccountUser { try await request("/api/auth/me") }

    func currentStudyAccess() async throws -> StudyAccess {
        try await request("/api/study/me")
    }

    func studyParticipants() async throws -> [StudyParticipant] {
        try await request("/api/admin/study-participants")
    }

    func studySchedules() async throws -> [StudySchedule] {
        try await request("/api/admin/study-schedules")
    }

    func updateStudySchedule(
        participantID: String,
        update: StudyScheduleUpdate
    ) async throws -> StudySchedule {
        let body = try jsonObject(update)
        return try await request(
            "/api/admin/study-schedules/\(participantID)",
            method: "PUT",
            body: body
        )
    }

    func logout() async throws {
        let _: EmptyResponse = try await request("/api/auth/logout", method: "POST")
    }

    func createReflectionSession(_ reflection: ReflectionSession) async throws -> String {
        struct Response: Decodable { let sessionId: String }
        let context = try jsonObject(reflection.context)
        var body: [String: Any] = ["condition": reflection.condition.rawValue, "context": context]
        if let sequence = reflection.studySequence, let period = reflection.studyPeriod {
            body["studySequence"] = sequence.rawValue
            body["studyPeriod"] = period
        }
        let response: Response = try await request("/api/sessions", method: "POST", body: body)
        return response.sessionId
    }

    func syncReflectionSession(id: String, reflection: ReflectionSession, action: String) async throws {
        let payload = try jsonObject(reflection)
        let _: SessionUpdateResponse = try await request("/api/sessions/\(id)", method: "PATCH", body: ["stage": reflection.stage.rawValue, "action": action, "payload": payload])
    }

    func deleteReflectionSession(id: String) async throws {
        let _: EmptyResponse = try await request("/api/sessions/\(id)", method: "DELETE")
    }

    func listReflectionSessions() async throws -> [RemoteSessionSummary] {
        try await request("/api/sessions")
    }

    func completeJSON(system: String, user: String, maxTokens: Int, temperature: Double, agentMode: String = "balanced") async throws -> String {
        struct Response: Decodable { let content: String }
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "maxTokens": maxTokens,
            "temperature": temperature,
            "agentMode": agentMode
        ]
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let response: Response = try await request(
                    "/api/llm/chat",
                    method: "POST",
                    body: body,
                    timeoutInterval: 150
                )
                return response.content
            } catch {
                lastError = error
                guard attempt == 0, isTransientLLMError(error) else { throw error }
                try await Task.sleep(for: .milliseconds(450))
            }
        }
        throw lastError ?? RemoteAPIError.invalidResponse
    }

    /// Current TurnController roles send typed context only. The server owns the immutable prompt
    /// text selected by `promptVersion`; Swift still validates every returned protocol decision.
    func completeTurnJSON<Payload: Encodable>(
        task: String,
        promptVersion: String,
        payload: Payload,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let body: [String: Any] = [
            "promptTask": task,
            "promptVersion": promptVersion,
            "payload": try jsonObject(payload),
            "maxTokens": maxTokens,
            "temperature": temperature,
        ]
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let response: TurnCompletionResponse = try await request(
                    "/api/llm/turn",
                    method: "POST",
                    body: body,
                    timeoutInterval: 150
                )
                return response.content
            } catch {
                lastError = error
                guard attempt == 0, isTransientLLMError(error) else { throw error }
                try await Task.sleep(for: .milliseconds(450))
            }
        }
        throw lastError ?? RemoteAPIError.invalidResponse
    }

    private func isTransientLLMError(_ error: Error) -> Bool {
        if let apiError = error as? RemoteAPIError,
           case .server(let status, _) = apiError {
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        if let urlError = error as? URLError {
            return [
                .timedOut,
                .cannotFindHost,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .notConnectedToInternet,
            ].contains(urlError.code)
        }
        return false
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Any? = nil,
        timeoutInterval: TimeInterval = 30
    ) async throws -> Response {
        guard let baseURL else { throw RemoteAPIError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw RemoteAPIError.server(status: http.statusCode, detail: detail ?? "服务器请求失败")
        }
        if Response.self == EmptyResponse.self, data.isEmpty { return EmptyResponse() as! Response }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Codable {}
private struct SessionUpdateResponse: Decodable { let sessionId: String; let stage: String }

enum RemoteAPIError: LocalizedError {
    case notConfigured, invalidResponse, server(status: Int, detail: String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "尚未配置 API_BASE_URL，请在 Config.xcconfig 中填写 HTTPS 后端地址"
        case .invalidResponse: "服务器返回无效响应"
        case .server(_, let detail): detail
        }
    }
}

struct CardService {
    /// This catalogue is local, fixed, and uniformly sampled. It records only visible composition:
    /// objects, their unfinished relationship, open image questions, and interpretations the
    /// system must not impose. Psychological meanings and Tender/Fierce responses live elsewhere.
    private struct Definition {
        let title: String
        let imageName: String
        let guidance: CardVisualGuidance
    }

    private let catalogue: [Definition] = [
        .init(title: "旅人", imageName: "旅人", guidance: guidance(
            "人物的一只脚已经离开岸边，另一只脚仍接近原处；船、木板与行李分处过渡两侧，下一步尚未发生。",
            anchors: ["岸", "船", "小船", "木板", "脚", "栏杆", "旅行袋", "包"],
            scaffolds: [
                scaffold([["脚"], ["岸", "木板", "船"]], "两只脚停在不同位置，让这个画面处在怎样的时刻？"),
                scaffold([["旅行袋", "包"], ["船", "木板"]], "地上的旅行袋和已经靠岸的小船之间，还有什么没有确定？"),
            ],
            prohibited: ["船代表命运或召唤", "人物必须立刻上船", "停在岸上就是逃避", "新开始一定比留下更好"]
        )),
        .init(title: "工匠", imageName: "工匠", guidance: guidance(
            "一个人面对未闭合的框架；多种工具、连接件和不同图纸方案同时摊在桌上，尚未选定怎样组合。",
            anchors: ["工匠", "工作台", "未完成框架", "框架", "工具", "螺丝刀", "钳子", "螺丝", "连接件", "图纸", "笔记本", "方案", "材料", "零件"],
            scaffolds: [
                scaffold([["框架"], ["工具", "螺丝", "连接件", "图纸"]], "尚未完成的框架和桌上的工具之间，可能还有哪一步没有确定？"),
                scaffold([["图纸", "笔记本", "方案"], ["未完成框架", "框架", "材料", "零件"]], "图纸里的几种方案与桌上尚未连接的材料之间，哪些选择还没有确定？"),
            ],
            prohibited: ["桌上的工具证明人物能够独自解决一切", "图纸已经给出唯一正确做法", "缺少他人出现证明人物必须独自完成", "未完成说明人物能力不足"]
        )),
        .init(title: "显影者", imageName: "显影者", guidance: guidance(
            "照片的一部分轮廓已经出现，另一部分仍不清楚；人物在计时器、托盘与夹子旁继续观察，处理尚未结束。",
            anchors: ["暗房", "照片", "轮廓", "夹子", "计时器", "托盘", "显影"],
            scaffolds: [
                scaffold([["照片"], ["轮廓", "显影"]], "照片里已经出现的部分和仍看不清的部分有什么不同？"),
                scaffold([["照片"], ["计时器", "托盘", "夹子"]], "人物为什么还在观察，而没有马上处理这张照片？"),
            ],
            prohibited: ["照片内容代表被压抑的记忆", "模糊的轮廓证明直觉一定正确", "显影状态证明用户具有某种行为模式或人格特征"]
        )),
        .init(title: "放下的照顾", imageName: "放下的照顾", guidance: guidance(
            "一些物品被放在两个人之间；一只手已经松开，另一只手尚未接住，物品接下来由谁怎样处理仍未确定。",
            anchors: ["两个人", "汤", "水", "毯子", "桌子", "手", "照顾"],
            scaffolds: [
                scaffold([["汤", "水", "毯子"], ["桌子", "两个人", "人"]], "被放在两个人之间的东西，让这个画面留下了什么选择？"),
                scaffold([["手"], ["汤", "水", "毯子"]], "一只手已经松开、另一只手还没有接住，这个停顿可能怎样继续？"),
            ],
            prohibited: ["接收者必须接受这份照顾", "拒绝照顾就是拒绝关系", "给予者一定最了解对方需要什么"]
        )),
        .init(title: "留出的开口", imageName: "留出的开口", guidance: guidance(
            "屏风位于书桌与门口之间，但没有完全封闭通道；门内外仍可相互看见或通行，屏风位置也仍可移动。",
            anchors: ["房间", "屏风", "书桌", "电脑", "门", "门口", "文件", "开口"],
            scaffolds: [
                scaffold([["屏风"], ["门", "门口", "开口"]], "屏风没有完全封住门口，这个位置同时保留了什么？"),
                scaffold([["屏风"], ["书桌", "电脑", "文件", "人"]], "如果屏风继续移动，房间两边的关系可能怎样变化？"),
            ],
            prohibited: ["屏风证明人物有控制欲", "门外的人一定在侵犯边界", "完全关闭或完全开放必然更健康"]
        )),
        .init(title: "传下来的图样", imageName: "传下来的图样", guidance: guidance(
            "旧图样、带修改痕迹的笔记和当前材料同时摊在工作桌上；两个人正在比较它们，尚未显示会遵循、修改或搁置哪一种。",
            anchors: ["工作室", "两个人", "旧图样", "模板", "图样", "笔记本", "材料", "尺子", "步骤"],
            scaffolds: [
                scaffold([["旧图样", "模板", "图样"], ["笔记本", "材料", "尺子"]], "旧图样、笔记本和桌上材料之间，有哪些相同或不同？"),
                scaffold([["材料"], ["旧图样", "模板", "图样", "两个人"]], "旁边几种材料，让原来的图样多出了哪些可能？"),
            ],
            prohibited: ["旧图样一定正确", "指向图样的人代表不可质疑的权威", "偏离模板就是失败", "既有规范必然是压迫"]
        )),
        .init(title: "两处之间", imageName: "两处之间", guidance: guidance(
            "两个人共同抬着一盆树，尚未把它放到明亮院落或阴影门廊中的任何一处；两个位置条件不同。",
            anchors: ["两个人", "树盆", "盆栽", "把手", "长凳", "门廊", "院落", "明亮", "阴影"],
            scaffolds: [
                scaffold([["树盆", "盆栽"], ["两个人", "把手"]], "两个人还没有放下树盆，这个共同停顿里可能各自在顾及什么？"),
                scaffold([["树盆", "盆栽"], ["长凳", "门廊", "明亮", "阴影"]], "画面中的两个位置，会让这盆树得到哪些不同条件？"),
            ],
            prohibited: ["画中两人一定是情侣", "关系好就应该自然同意", "某一方必须让步", "树盆的位置能够决定关系结果"]
        )),
        .init(title: "岔路与载重", imageName: "岔路与载重", guidance: guidance(
            "装有物件的三轮车停在分叉道路前；部分物件在车上，另一个在路边，其来去方向和接下来的位置都未确定。",
            anchors: ["三轮车", "车", "箱子", "货物", "路边物件", "袋子", "岔路", "道路", "绳子"],
            scaffolds: [
                scaffold([["车", "三轮车"], ["岔路", "道路"]], "车停在分叉处时，不同方向各自带来了什么？"),
                scaffold([["车", "三轮车"], ["箱子", "货物", "负荷"]], "车上的载重可能怎样影响它接下来的方向和速度？"),
                scaffold([["车", "三轮车", "货物"], ["路边物件", "袋子"]], "车上和路边的物件处在不同位置，这个状态还可能怎样变化？"),
            ],
            prohibited: ["人物必须继续向前", "路边物件必然是主动卸下的负担", "较慢说明意志不够", "某条路是唯一正确方向"]
        )),
        .init(title: "风未停", imageName: "风未停", guidance: guidance(
            "风仍在吹动晾衣绳上的布；人物手边有夹子和绳子，但布与绳的位置仍在变化。",
            anchors: ["院子", "风", "布", "晾衣绳", "夹子", "绳子", "手"],
            scaffolds: [
                scaffold([["布"], ["风", "晾衣绳"]], "风还没有停时，这块布正在怎样改变自己的位置？"),
                scaffold([["手"], ["夹子", "绳子", "布"]], "人物手里的夹子或绳子，可能让画面接下来出现哪些不同变化？"),
            ],
            prohibited: ["布代表需要被驯服的情绪", "稳定就是压住所有反应", "人物必须用力量控制整块布"]
        )),
        .init(title: "暂时关上的门", imageName: "暂时关上的门", guidance: guidance(
            "门暂时关闭；房间内有书、水和计时器，门边仍留有手机或便签等联系入口，关闭会持续多久尚未显示。",
            anchors: ["房间", "桌子", "书", "水", "计时器", "闹钟", "手机", "门", "便签"],
            scaffolds: [
                scaffold([["门"], ["便签", "手机", "物品"]], "门暂时关着，旁边留下的联系入口让这个独处有什么范围？"),
                scaffold([["计时器", "闹钟"], ["书", "水", "桌子"]], "计时器和桌上的东西，可能怎样提示这段独处的开始或结束？"),
            ],
            prohibited: ["独处说明用户有心理疾病", "关门就是拒绝所有关系", "人物必须马上重新联系别人"]
        )),
        .init(title: "雨中的新摆法", imageName: "雨中的新摆法", guidance: guidance(
            "雨改变了市集现场；旧布局图与新摆放、雨棚下物件同时存在，布置仍可继续调整。",
            anchors: ["雨", "市集", "摊位", "雨棚", "布局图", "图", "陶器", "植物", "箱子"],
            scaffolds: [
                scaffold([["布局图", "图"], ["雨", "雨棚", "摊位"]], "旧布局图和新布局图，分别对应了怎样的现场条件？"),
                scaffold([["陶器", "植物", "箱子"], ["摊位", "雨棚"]], "这些物品重新摆放后，摊位可能出现哪些不同？"),
            ],
            prohibited: ["下雨说明命运正在转变", "旧计划完全错误", "所有变化都能靠积极态度解决"]
        )),
        .init(title: "倾斜之后", imageName: "倾斜之后", guidance: guidance(
            "架子已经倾斜，脚轮或连接件有损坏；部分陶器仍在架上，另一些已被取下，空位和重量分布已经改变。",
            anchors: ["架子", "陶器", "脚轮", "连接件", "陶罐", "空位", "倾斜", "重量"],
            scaffolds: [
                scaffold([["架子"], ["倾斜", "脚轮", "连接件"]], "架子的倾斜和损坏的部件之间，画面提供了哪些线索？"),
                scaffold([["陶罐", "陶器"], ["空位", "架子", "重量"]], "被取下的陶罐和架上留下的空位，怎样改变了现在的局面？"),
            ],
            prohibited: ["架子损坏证明没有人需要负责", "取下陶罐的人一定有错", "画面能够裁定谁应承担全部责任"]
        )),
        .init(title: "倒置之后", imageName: "倒置之后", guidance: guidance(
            "同一花瓶主题以正向和倒置两幅图并列；人物停在两幅图之间，笔尚未继续落下。",
            anchors: ["工作室", "两幅图", "画", "花瓶", "花朵", "倒置", "笔"],
            scaffolds: [
                scaffold([["两幅图", "画"], ["花瓶", "花朵", "倒置"]], "同一主题在两个方向里，哪些部分改变了，哪些仍然相同？"),
                scaffold([["人"], ["两幅图", "画", "笔"]], "人物停在两幅图之间时，可能正在比较什么？"),
            ],
            prohibited: ["倒置版本揭示了唯一真相", "暂停一定是逃避", "改变看法说明过去完全错误"]
        )),
        .init(title: "离开之前", imageName: "离开之前", guidance: guidance(
            "一些物品已经装箱，另一些仍留在房间；人物拿着钥匙站在门边，离开、返回或继续整理都尚未发生。",
            anchors: ["房间", "门", "钥匙", "纸箱", "箱子", "照片", "盆栽", "画框", "轮廓", "物品"],
            scaffolds: [
                scaffold([["纸箱", "箱子"], ["照片", "盆栽", "物品"]], "已经封好的箱子和仍留在房间里的东西，分别处在怎样的状态？"),
                scaffold([["钥匙"], ["门", "房间"]], "人物拿着钥匙站在门边，这个时刻还没有完成什么？"),
            ],
            prohibited: ["结束必然带来成长", "人物必须把所有东西都留下或带走", "离开证明一段关系或身份没有价值"]
        )),
        .init(title: "分水", imageName: "分水", guidance: guidance(
            "同一水源经过多个出水口流入大小和水位不同的容器；人物在旁观察，尚未调整出水口或容器位置。",
            anchors: ["水箱", "水龙头", "水槽", "出水口", "容器", "水缸", "水", "水位", "温室", "观察者"],
            scaffolds: [
                scaffold([["水箱", "水龙头", "水槽"], ["容器", "水缸"]], "同一水源流向几个容器时，水流和水位有哪些不同？"),
                scaffold([["观察者", "人物"], ["水槽", "出水口", "容器"]], "人物站在水槽和容器旁边时，接下来还可能出现哪些不同变化？"),
            ],
            prohibited: ["几个容器水量相同才公平", "人物已经决定重新分配水流", "水量代表用户的情绪或能量数值"]
        )),
        .init(title: "缠住门的藤", imageName: "缠住门的藤", guidance: guidance(
            "藤蔓原先被绳子引向棚架，如今也经过门把手与门框；人物正在查看门与藤蔓的状态，工具留在旁边。",
            anchors: ["藤蔓", "藤", "果实", "绳子", "棚架", "门把手", "门框", "门", "温室", "园丁", "工具篮", "手套", "小铲子"],
            scaffolds: [
                scaffold([["藤蔓", "藤"], ["绳子", "棚架", "门把手"]], "藤蔓原先被引向棚架，现在又缠住门把手，这条路径是怎样延续的？"),
                scaffold([["园丁", "人物"], ["门框", "门", "藤蔓", "藤"]], "人物扶着门框查看藤蔓时，门边有哪些状态还没有确定？"),
            ],
            prohibited: ["藤蔓证明用户成瘾或意志薄弱", "人物已经决定剪断藤蔓", "曾经有效的模式现在必然完全有害"]
        )),
        .init(title: "旧痕新漏", imageName: "旧痕新漏", guidance: guidance(
            "旧水渍附近出现新裂缝和漏水；一人检查上方，另一人移动书，接水与查找来源同时进行。",
            anchors: ["雨", "天花板", "水渍", "裂缝", "漏水", "桶", "积水", "墙皮", "手电", "书", "书架"],
            scaffolds: [
                scaffold([["水渍", "旧痕"], ["裂缝", "漏水"]], "旧水渍和新出现的裂缝，让人能看见哪些不同时间留下的痕迹？"),
                scaffold([["人"], ["手电", "裂缝", "书", "书架"]], "一人检查裂缝、另一人移动书，这两个动作正在分别处理什么？"),
            ],
            prohibited: ["裂缝代表用户已经破碎", "漏水证明用户造成了全部问题", "暂时接水等于拒绝面对结构问题"]
        )),
        .init(title: "暮色中的补给", imageName: "暮色中的补给", guidance: guidance(
            "水瓶正在被补满，背包与食物等物件暂放在长凳；远处道路仍继续，停留多久和之后方向未知。",
            anchors: ["傍晚", "暮色", "休息点", "背包", "饮水处", "水瓶", "长凳", "食物", "毛巾", "外套", "路灯", "道路"],
            scaffolds: [
                scaffold([["水瓶", "饮水处"], ["道路", "路灯"]], "水瓶正在被补满，而远处道路仍在继续，这两个部分怎样同时留在画面里？"),
                scaffold([["背包"], ["长凳", "食物", "毛巾", "外套"]], "放下的背包和长凳上的补给，让这个停留可能有哪些不同用途？"),
            ],
            prohibited: ["希望等于保持乐观", "一次补给能够解决所有耗损", "继续上路是唯一正确选择"]
        )),
        .init(title: "等待中的轮廓", imageName: "等待中的轮廓", guidance: guidance(
            "雨夜玻璃上的侧脸倒影与外部灯光重叠；擦开的局部更清楚，但灯光来源与远处轮廓仍无法确认。",
            anchors: ["雨夜", "公交站", "玻璃", "倒影", "轮廓", "灯光", "公交车", "手机", "手", "雨"],
            scaffolds: [
                scaffold([["玻璃"], ["倒影", "轮廓", "灯光"]], "玻璃上的侧脸倒影和外面的灯光重叠后，哪些部分更清楚，哪些更难确认？"),
                scaffold([["玻璃"], ["擦开", "雨", "灯光", "公交车"]], "擦开的这一小块提供了什么线索，又还没有回答什么？"),
            ],
            prohibited: ["情绪是虚假的", "远处灯光一定来自公交车", "倒影代表用户的潜意识或真实自我"]
        )),
        .init(title: "风筝升起之后", imageName: "风筝升起之后", guidance: guidance(
            "经过修补的风筝已经升空，人物仍握着线轴；地面留有备用材料，空中状态仍受风和线维持。",
            anchors: ["风筝", "修补", "天空", "草地", "线轴", "风筝线", "袋", "材料", "备用线", "花"],
            scaffolds: [
                scaffold([["风筝"], ["修补", "风筝线", "线轴"]], "风筝已经升起，修补痕迹和手里的线还在共同维持什么？"),
                scaffold([["风筝"], ["袋", "材料", "备用线", "花"]], "空中的风筝和地面留下的材料，让这个成果显得怎样既完成又仍可变化？"),
            ],
            prohibited: ["风筝升起证明困难已经结束", "修补痕迹说明成果不完整", "好的状态必须永久保持才算成功"]
        )),
        .init(title: "旧物与晨钟", imageName: "旧照片与晨钟", guidance: guidance(
            "旧照片留在桌上，门外的钟正在摆动；人物已从椅子起身但双脚仍在室内，下一步尚未发生。",
            anchors: ["清晨", "房间", "桌子", "旧照片", "照片", "椅子", "门", "晨钟", "钟", "双脚"],
            scaffolds: [
                scaffold([["旧照片", "照片"], ["门", "晨钟", "钟"]], "桌上的旧照片和门外摆动的钟，把人物放在了怎样的两个方向之间？"),
                scaffold([["人"], ["椅子", "桌子", "门", "双脚"]], "人物已经站起、双脚却仍在室内，这个瞬间还有什么尚未发生？"),
            ],
            prohibited: ["钟声代表命运的召唤", "现在看清就证明过去的自己有罪", "人物必须立刻离开房间"]
        )),
        .init(title: "最后一块", imageName: "最后一块", guidance: guidance(
            "马赛克整体已经形成，边缘仍有缺口；人物手里的拼片大致相合，工具箱里也还有材料，是否继续修改未确定。",
            anchors: ["马赛克", "桌面", "颜色", "形状", "材料", "缺口", "拼片", "最后一块", "工具箱", "手"],
            scaffolds: [
                scaffold([["马赛克", "桌面"], ["缺口", "拼片", "最后一块"]], "手里的拼片大致相合却不一定严丝合缝，这让桌面可能怎样结束？"),
                scaffold([["工具箱", "材料"], ["马赛克", "桌面", "缺口"]], "工具箱里还有材料时，画面怎样区分继续修改和已经足够完整？"),
            ],
            prohibited: ["最后一块必须严丝合缝", "还有材料就说明不能结束", "完成意味着以后不再需要调整"]
        )),
    ]

    /// Reality-translated Major Arcana relationships. Array order is deliberately identical to
    /// the fixed visual catalogue. These remain local and closed until Swift has committed a
    /// user-grounded image-to-life mapping for the selected card.
    private let referenceCatalogue: [CardReferenceGuidance] = [
        reference(
            ["开始行动与继续准备之间的关系", "进入未知与保留退路之间的关系"],
            activation: "只有当用户自己提到尚未完全出发，或一部分向前、一部分留在原处时，才可探索缺少的是必要条件还是对完全确定的等待。",
            prohibited: ["不能直接解释为用户害怕开始", "不能说用户应该勇敢迈出第一步"]
        ),
        reference(
            ["已有材料与下一步行动之间的关系", "多个可行方案与尚未确定的组合方式之间的关系"],
            activation: "只有当用户自己注意到工具、材料和部分完成的框架已经在场，但具体采用什么零件、如何组合或先完成哪一步仍未确定时，才可以探索现有资源怎样转化为一个实际动作。",
            prohibited: [
                "不能直接说用户有能力或缺乏行动力",
                "不能假定存在唯一正确的方案",
                "不能要求用户寻求画面中并不存在的外部帮助",
            ]
        ),
        reference(
            ["已经显现的信息与仍不清楚的部分之间的关系", "观察到的事实与由此产生的解释之间的关系"],
            activation: "只有当用户自己注意到部分轮廓已经出现但整体仍不能确定时，才可探索事实、感受、推测和未知。",
            prohibited: ["不能把模糊画面解释成潜意识真相", "不能宣称存在隐藏答案"]
        ),
        reference(
            ["提供照顾与实际需要之间的关系", "给出支持与是否接受支持之间的关系"],
            activation: "只有当用户注意到照顾已经放下但尚未被接过，或现实中提到帮助是否合适时，才可探索支持的形式、程度和接受方式。",
            prohibited: ["不能直接说用户需要被照顾", "不能假定提供帮助的人一定善意或正确"]
        ),
        reference(
            ["开放接触与保护空间之间的关系", "提供稳定的结构与造成限制的结构之间的关系"],
            activation: "只有当用户自己把屏风、门口或工作空间解释为接触范围时，才可探索什么需要开放、什么需要保护，以及边界当前产生的作用。",
            prohibited: ["不能判断用户控制欲强或缺乏边界", "不能说用户需要把别人挡在外面"]
        ),
        reference(
            ["既有图样与当前制作条件之间的关系", "借用他人经验与形成个人判断之间的关系"],
            activation: "只有当用户自己注意到两个人正在共同查看旧图样、当前草稿和实际材料，并把这种比较联系到现实中的标准、惯例或他人经验时，才可以探索哪些部分仍适用、哪些需要调整。",
            prohibited: [
                "不能说经验丰富的人一定拥有正确答案",
                "不能把参考旧方法解释为缺乏独立思考",
                "不能预设传统必须被遵循或打破",
            ]
        ),
        reference(
            ["不同需要与共同决定之间的关系", "个人偏好与关系后果之间的关系"],
            activation: "只有当用户注意到多人共同处理同一物件却面对不同位置时，才可探索各方需要、代价和共同影响。",
            prohibited: ["不能固定解释为爱情或关系危机", "不能断言用户必须二选一"]
        ),
        reference(
            ["前进方向与当前携带内容之间的关系", "已经装载、暂时放下与是否重新带走之间的关系"],
            activation: "只有当用户自己注意到人物停在岔路前，同时车内物件和路边袋子的去留仍未确定，并把这种关系联系到现实中的方向、任务、承诺或条件时，才可以探索选择路线与决定携带什么如何相互影响。",
            prohibited: [
                "不能说用户必须放下负担",
                "不能假定路边的袋子应该被舍弃或带回",
                "不能把停顿解释为逃避、犹豫或缺乏方向",
            ]
        ),
        reference(
            ["强烈力量持续存在与如何回应它之间的关系", "固定、松开与重新安排之间的关系"],
            activation: "只有当用户把风、布或固定动作联系到现实中的强烈情绪或压力时，才可探索情绪仍在时如何回应。",
            prohibited: ["不能说用户需要控制情绪或变得坚强", "不能说用户应该压住冲动"]
        ),
        reference(
            ["暂时退开与持续失联之间的关系", "独处的恢复作用与重新连接的时机之间的关系"],
            activation: "只有当用户把关门、安静空间或重新联系线索对应到现实中的独处时，才可探索独处的目的、范围与结束信号。",
            prohibited: ["不能把独处解释为逃避、孤独或自我照顾"]
        ),
        reference(
            ["原计划与变化后的现实条件之间的关系", "不可控制的变化与仍可调整的部分之间的关系"],
            activation: "只有当用户提到条件变化使旧安排不再适用时，才可探索哪些目标和方法需要更新。",
            prohibited: ["不能说用户必须顺其自然", "不能把结果归因于命运"]
        ),
        reference(
            ["个人行为、他人行为与结构条件之间的关系", "已经造成的影响与责任范围之间的关系"],
            activation: "只有当用户注意到重量、空位、损坏部件和不同人物动作时，才可探索影响来源及可控制或可修复部分。",
            prohibited: ["不能直接判定谁有错", "不能依据牌面分配责任"]
        ),
        reference(
            ["暂停观察与继续行动之间的关系", "改变视角与是否获得新信息之间的关系"],
            activation: "只有当用户提到同一内容从不同方向呈现，或现实中正在重新考虑时，才可探索换角度后实际看见了什么。",
            prohibited: ["不能把所有停顿解释为成长", "不能默认用户只需要换一个视角"]
        ),
        reference(
            ["已经结束的部分与仍需处理的部分之间的关系", "离开、带走与留下之间的关系"],
            activation: "只有当用户注意到空间已搬空但仍有物件未处理，或现实中某阶段事实上已经结束时，才可探索还需告别、交接、修复或保留什么。",
            prohibited: ["不能说用户应该放下过去", "不能说用户应该迎接新生"]
        ),
        reference(
            ["同一来源与不同接收容量之间的关系", "已经流向各处的投入与各处实际需要之间的关系"],
            activation: "只有当用户自己注意到同一水源流向大小、状态或容量不同的容器，并将其联系到现实中不同任务、关系或需要接受同一种资源的方式时，才可以探索当前投入是否适合各处的实际容量。",
            prohibited: [
                "不能直接说用户需要保持平衡",
                "不能假定平均分配就是公平",
                "不能因为容器大小不同就替用户决定哪一处应该获得更多",
            ]
        ),
        reference(
            ["曾经支持生长的路径与后来影响通行之间的关系", "保留已有生长与重新引导、松开或局部处理之间的关系"],
            activation: "只有当用户自己注意到藤蔓沿既有支架生长并已经结果，但同时进入门口、影响通道，并将其联系到现实中某种过去有效、现在开始产生限制的做法时，才可以探索这套方式曾经发挥了什么作用，以及目前带来了什么代价。",
            prohibited: [
                "不能诊断用户被束缚、成瘾或缺乏自控",
                "不能说用户必须彻底切断某种模式",
                "不能假定人物已经决定修剪藤蔓",
            ]
        ),
        reference(
            ["突发冲击与既有结构脆弱处之间的关系", "紧急处理与后续重建之间的关系"],
            activation: "只有当用户提到新问题出现在旧痕附近，或现实事件暴露了原有安排的问题时，才可探索突发条件和长期脆弱点。",
            prohibited: ["不能说用户毁掉了一切", "不能把冲击解释为必要成长"]
        ),
        reference(
            ["继续前进与补充资源之间的关系", "当前耗损与下一步所需条件之间的关系"],
            activation: "只有当用户自己注意到道路仍继续、人物正在补水、休息或整理资源时，才可探索需要恢复的具体内容。",
            prohibited: ["不能说用户需要疗愈或应该保持希望", "不能说用户已经走出低谷"]
        ),
        reference(
            ["不完整信息与当前解释之间的关系", "真实感受与外部事实之间的关系"],
            activation: "只有当用户提到倒影、模糊灯光、无法确认外部对象，或现实中缺少关键信息时，才可探索事实、感受、预测和未知。",
            prohibited: ["不能把不安解释成直觉正确", "不能说用户想太多"]
        ),
        reference(
            ["已经取得的进展与促成它的条件之间的关系", "享受成果与将成果转化为新压力之间的关系"],
            activation: "只有当用户注意到成果已经出现但人物仍在调整时，才可探索哪些进展真实发生，以及如何维持而不立即提高标准。",
            prohibited: ["不能直接说用户成功或应该自信", "不能说一切已经好转"]
        ),
        reference(
            ["重新看待过去与回应当前认识之间的关系", "已经看清的内容与接下来是否行动之间的关系"],
            activation: "只有当用户把旧物、起身、门外声响理解为回顾和回应时，才可探索重新看清了什么，以及这份认识是否需要现实回应。",
            prohibited: ["不能把声响解释为命运召唤", "不能说用户必须告别过去或进入新阶段"]
        ),
        reference(
            ["整体已经形成与仍有缺口之间的关系", "继续完善与决定完成之间的关系"],
            activation: "只有当用户提到作品基本完成但仍有不完全吻合之处，或现实项目已达到可交付状态时，才可探索什么必须完成、什么可以保留为不完美。",
            prohibited: ["不能说用户已经圆满", "不能把停止修改等同于降低标准"]
        ),
    ]

    var allCards: [ReflectionCard] {
        catalogue.enumerated().map { index, definition in
            return ReflectionCard(
                id: index,
                neutralLabel: String(format: "图像卡 %02d", index + 1),
                title: definition.title,
                imageName: definition.imageName,
                visualGuidance: definition.guidance,
                referenceGuidance: referenceCatalogue.indices.contains(index)
                    ? referenceCatalogue[index]
                    : nil
            )
        }
    }

    /// Resolves private reference guidance from the immutable local catalogue rather than trusting
    /// a copy restored inside a saved session. Both the stable Major Arcana index and current image
    /// resource must agree, so stale or malformed card payloads cannot borrow another card's lens.
    func canonicalReferenceGuidance(
        for card: ReflectionCard
    ) -> CardReferenceGuidance? {
        guard allCards.indices.contains(card.id) else { return nil }
        let canonical = allCards[card.id]
        guard canonical.id == card.id,
              canonical.imageName == card.imageName else {
            return nil
        }
        return canonical.referenceGuidance
    }

    func draw() -> ReflectionCard {
        // `allCards` is non-empty by construction; the fallback only protects a malformed future
        // catalogue without allowing route, emotion, or tracking data to affect selection.
        allCards.randomElement() ?? ReflectionCard(
            id: 0,
            neutralLabel: "图像卡 01",
            title: "旅人",
            imageName: "旅人"
        )
    }

    private static func guidance(
        _ observableRelation: String,
        anchors: [String],
        scaffolds: [CardVisualScaffold] = [],
        prohibited: [String] = []
    ) -> CardVisualGuidance {
        CardVisualGuidance(
            observableRelation: observableRelation,
            visualAnchors: anchors,
            prohibitedClaims: [
                "不要从画面推断人格或心理状态",
                "不要把画中人物等同于用户或特定他人",
                "不要把设计者记录的视觉关系说成用户应当猜中的答案",
                "不要用牌义覆盖用户自己的解释",
            ] + prohibited,
            visualScaffolds: scaffolds
        )
    }

    /// The question can only be used after every group has appeared in the person's own image
    /// narrative. `AppServices` owns these card-specific image affordances; the view model only
    /// owns when one may be used and how many attempts are allowed.
    private static func scaffold(
        _ requiredAnchorGroups: [[String]],
        _ question: String
    ) -> CardVisualScaffold {
        CardVisualScaffold(
            requiredAnchorGroups: requiredAnchorGroups,
            question: question
        )
    }

    private static func reference(
        _ relations: [String],
        activation: String,
        prohibited: [String]
    ) -> CardReferenceGuidance {
        CardReferenceGuidance(
            relations: relations,
            activationBoundary: activation,
            prohibitedClaims: prohibited
        )
    }

}

/// The overlap is computed locally so a model never gets to select a card or workflow state.
/// The card contributes only an anchor check; the relationship comes entirely from user-grounded
/// image and reality relations. It is not compared with a designer meaning catalogue.
struct CardGroundingMatcher {
    func match(
        card: ReflectionCard,
        userImageNarrative: String,
        semanticRelations: [SemanticRelation]
    ) -> CardGroundingMatch? {
        guard let guidance = card.visualGuidance else { return nil }
        let image = comparable(userImageNarrative)
        let anchors = guidance.visualAnchors.filter { anchor in
            let normalized = comparable(anchor)
            // Single-character Chinese anchors such as 门、灯、路 are meaningful in the
            // card-specific catalogue. The old > 1 guard silently disabled guidance for many
            // otherwise valid image descriptions.
            return !normalized.isEmpty && image.contains(normalized)
        }
        guard !anchors.isEmpty else { return nil }

        let imageRelations = groundedRelations(.imageStructure, from: semanticRelations)
        let realityRelations = groundedRelations(.realityStructure, from: semanticRelations)
        guard !imageRelations.isEmpty, !realityRelations.isEmpty else { return nil }

        var best: (
            image: SemanticRelation,
            reality: SemanticRelation,
            concepts: Set<SemanticConcept>
        )?
        for imageRelation in imageRelations {
            let imageConcepts = Set(imageRelation.concepts)
            for realityRelation in realityRelations {
                let sharedConcepts = imageConcepts.intersection(realityRelation.concepts)
                guard !sharedConcepts.isEmpty else { continue }
                if best == nil || sharedConcepts.count > best!.concepts.count {
                    best = (imageRelation, realityRelation, sharedConcepts)
                }
            }
        }
        guard let best else { return nil }
        return CardGroundingMatch(
            matchedVisualAnchors: anchors,
            imageRelation: relationSummary(best.image),
            realityRelation: relationSummary(best.reality),
            matchedConcepts: Array(best.concepts).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func groundedRelations(
        _ kind: SemanticRelationKind,
        from relations: [SemanticRelation]
    ) -> [SemanticRelation] {
        relations.filter {
            $0.kind == kind &&
            [.userStated, .userConfirmed].contains($0.status) &&
            $0.confidence >= 0.6 &&
            !$0.evidence.isEmpty &&
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func relationSummary(_ relation: SemanticRelation) -> String {
        "\(relation.source) \(relation.relation) \(relation.target)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func comparable(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "、", with: "")
            .replacingOccurrences(of: "？", with: "")
            .replacingOccurrences(of: "！", with: "")
    }

}

/// Validates an Analyzer-proposed response function before it can reach the Writer. The model may
/// choose a useful semantic direction, while Swift retains authority over evidence, permissions,
/// question count, card use, action, and workflow state.
struct ResponsePlanValidator {
    func validate(
        _ candidate: ResponsePlan?,
        analysis: ContextAnalysis,
        state: ReflectionState,
        workflowPhase: ReflectionWorkflowPhase,
        messages: [ChatMessage]
    ) -> ResponsePlan? {
        guard let plan = candidate?.validated,
              plan.confidence >= 0.55,
              !plan.focus.isEmpty,
              !plan.evidence.isEmpty,
              allowedFunctions(for: state, workflowPhase: workflowPhase).contains(plan.function)
        else {
            return nil
        }

        let transcript = comparable(
            messages
                .filter { $0.role == .user }
                .map(\.content)
                .joined(separator: " ")
        )
        let latestUserTurn = comparable(
            messages.last(where: { $0.role == .user })?.content ?? ""
        )
        guard plan.evidence.allSatisfy({
            let fragment = comparable($0)
            return fragment.count >= 2 && transcript.contains(fragment)
        }),
        plan.evidence.contains(where: {
            let fragment = comparable($0)
            return fragment.count >= 2 && latestUserTurn.contains(fragment)
        }) else {
            return nil
        }

        let grounded = analysis.validated.resolvedSemanticRelations.filter { relation in
            [.userStated, .userConfirmed].contains(relation.status) &&
                relation.confidence >= 0.6 &&
                !relation.evidence.isEmpty &&
                relation.evidence.allSatisfy {
                    let fragment = comparable($0)
                    return fragment.count >= 2 && transcript.contains(fragment)
                }
        }
        guard !plan.relationKinds.isEmpty,
              plan.relationKinds.allSatisfy({ kind in
                  grounded.contains { $0.kind == kind }
              }),
              functionEvidenceIsAllowed(plan.function, grounded: grounded)
        else {
            return nil
        }

        if plan.shouldAskQuestion == false,
           ![.synthesizeNarrative, .closeWithoutQuestion].contains(plan.function) {
            return nil
        }
        return plan
    }

    private func functionEvidenceIsAllowed(
        _ function: ResponseFunction,
        grounded: [SemanticRelation]
    ) -> Bool {
        let kinds = Set(grounded.map(\.kind))
        switch function {
        case .exploreLivedExperience:
            return kinds.contains(.eventExperience)
        case .clarifyPersonalMeaning:
            return !kinds.isDisjoint(with: [.selfEvaluation, .unmetNeed, .uncertainty])
        case .clarifyCircumstances:
            return !kinds.isDisjoint(
                with: [.conditionCapacity, .boundaryNeed, .unmetNeed, .uncertainty, .behaviorImpact]
            )
        case .synthesizeTenderUnderstanding, .deepenTenderUnderstanding:
            return !kinds.isEmpty
        case .contextualizeTracking:
            return !kinds.isDisjoint(with: [.conditionCapacity, .uncertainty])
        case .developImageRelation:
            return kinds.contains(.imageStructure)
        case .connectImageToReality:
            return kinds.contains(.imageStructure) && kinds.contains(.realityStructure)
        case .explorePerspectiveShift:
            return kinds.contains(.imageRealityMapping) || kinds.contains(.meaningShift)
        case .exploreAgencyBoundaryOrChange:
            return !kinds.isDisjoint(with: [.behaviorImpact, .boundaryNeed, .controllablePart])
        case .synthesizeNarrative, .confirmUnderstanding:
            return !kinds.isEmpty
        case .proposePractice:
            return !kinds.isDisjoint(with: [.behaviorImpact, .boundaryNeed, .controllablePart, .unmetNeed])
        case .closeWithoutQuestion:
            return kinds.contains(.uncertainty)
        }
    }

    func allowedFunctions(
        for state: ReflectionState,
        workflowPhase: ReflectionWorkflowPhase
    ) -> Set<ResponseFunction> {
        switch state {
        case .eventDisclosure, .emotionDisclosure, .bodilyResponse, .selfJudgment,
             .contextDisclosure:
            return [
                .exploreLivedExperience,
                .clarifyPersonalMeaning,
                .clarifyCircumstances,
                .synthesizeTenderUnderstanding,
                .closeWithoutQuestion,
            ]
        case .tenderGrounding, .tenderExploration:
            return [.deepenTenderUnderstanding, .confirmUnderstanding, .closeWithoutQuestion]
        case .trackingReview:
            return [.contextualizeTracking, .confirmUnderstanding, .closeWithoutQuestion]
        case .readinessCheck:
            return [.confirmUnderstanding, .deepenTenderUnderstanding, .closeWithoutQuestion]
        case .cardInterpretation:
            return [.developImageRelation, .closeWithoutQuestion]
        case .attributionReflection:
            switch workflowPhase {
            case .cardConnection:
                return [.connectImageToReality, .closeWithoutQuestion]
            case .cardMappingConfirmation:
                return [.confirmUnderstanding, .closeWithoutQuestion]
            case .candidCircumstances:
                return [.deepenTenderUnderstanding, .closeWithoutQuestion]
            case .cardMeaningShift:
                return [.explorePerspectiveShift, .closeWithoutQuestion]
            case .candidAgency:
                return [.exploreAgencyBoundaryOrChange, .closeWithoutQuestion]
            case .reflectionNarrativeConfirmation, .narrativeConfirmation:
                return [
                    .synthesizeNarrative, .confirmUnderstanding, .proposePractice,
                    .closeWithoutQuestion,
                ]
            case .optionalAction, .actionConfirmation:
                return [.proposePractice, .confirmUnderstanding, .closeWithoutQuestion]
            default:
                return [.confirmUnderstanding, .closeWithoutQuestion]
            }
        case .actionSelection:
            return [.proposePractice, .closeWithoutQuestion]
        case .summary:
            return [.synthesizeNarrative, .closeWithoutQuestion]
        case .welcome, .trackingPermission, .cardIntroduction, .completed, .safetySupport:
            return [.closeWithoutQuestion]
        }
    }

    /// Recovers only the conversational function when the Analyzer supplied valid semantic
    /// relations but omitted or malformed `responsePlan`. This remains domain-neutral: no topic,
    /// scenario word, or missing disclosure field decides the result. A recovered plan must still
    /// cite literal evidence from the latest user turn and pass the same phase/evidence validator
    /// as a model-authored plan.
    func recoverDisclosurePlan(
        analysis: ContextAnalysis,
        state: ReflectionState,
        workflowPhase: ReflectionWorkflowPhase,
        messages: [ChatMessage]
    ) -> ResponsePlan? {
        guard [
            ReflectionState.eventDisclosure,
            .emotionDisclosure,
            .bodilyResponse,
            .selfJudgment,
            .contextDisclosure,
        ].contains(state) else {
            return nil
        }

        let transcript = comparable(
            messages
                .filter { $0.role == .user }
                .map(\.content)
                .joined(separator: " ")
        )
        let latestUserTurn = comparable(
            messages.last(where: { $0.role == .user })?.content ?? ""
        )
        guard !latestUserTurn.isEmpty else { return nil }

        let grounded = analysis.validated.resolvedSemanticRelations.filter { relation in
            [.userStated, .userConfirmed].contains(relation.status) &&
                relation.confidence >= 0.6 &&
                !relation.evidence.isEmpty &&
                relation.evidence.allSatisfy {
                    let fragment = comparable($0)
                    return fragment.count >= 2 && transcript.contains(fragment)
                } &&
                relation.evidence.contains {
                    let fragment = comparable($0)
                    return fragment.count >= 2 && latestUserTurn.contains(fragment)
                }
        }

        // Recovery is intentionally narrower than normal model planning. An omitted plan must
        // not let an arbitrary condition/behavior relation redirect the whole disclosure. The
        // high-value exception is an explicit whole-self evaluation: ignoring it to collect a
        // missing emotion is exactly the conversational failure this compatibility path prevents.
        let priority: [(Set<SemanticRelationKind>, ResponseFunction, String)] = [
            (
                [.selfEvaluation],
                .clarifyPersonalMeaning,
                "clarify the concrete concern or personal meaning behind the user's self-evaluation"
            ),
        ]

        guard let (relation, function, questionIntent) = priority.lazy.compactMap({
            kinds, function, questionIntent -> (SemanticRelation, ResponseFunction, String)? in
            guard allowedFunctions(for: state, workflowPhase: workflowPhase).contains(function),
                  let relation = grounded.first(where: { kinds.contains($0.kind) }) else {
                return nil
            }
            return (relation, function, questionIntent)
        }).first else {
            return nil
        }

        let latestEvidence = relation.evidence.filter {
            latestUserTurn.contains(comparable($0))
        }
        let remainingEvidence = relation.evidence.filter {
            !latestEvidence.contains($0)
        }
        let evidence = Array((latestEvidence + remainingEvidence).prefix(3))
        let candidate = ResponsePlan(
            function: function,
            focus: "\(relation.source) \(relation.relation) \(relation.target)",
            evidence: evidence,
            relationKinds: [relation.kind],
            questionIntent: questionIntent,
            shouldAskQuestion: true,
            confidence: relation.confidence
        )
        return validate(
            candidate,
            analysis: analysis,
            state: state,
            workflowPhase: workflowPhase,
            messages: messages
        )
    }

    private func comparable(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

struct SafetyService {
    private let signals = [
        "自杀", "不想活", "活不下去", "想死", "不如死了", "结束生命", "结束自己",
        "伤害自己", "伤害我自己", "割腕", "跳楼", "suicide", "kill myself", "self-harm",
    ]
    func requiresInterrupt(_ text: String) -> Bool { signals.contains { text.localizedCaseInsensitiveContains($0) } }
}

/// Chooses the kind of optional practice from domain-neutral relations that Swift has already
/// verified against the user's transcript. It does not inspect topics, people, diagnoses, or
/// scenario words, and it never creates an action itself.
struct CompassionatePracticeResolver {
    func resolve(
        analysis: ContextAnalysis,
        groundedRelations: [SemanticRelation]
    ) -> CompassionatePracticeDirection {
        let behaviorImpacts = groundedRelations.filter { $0.kind == .behaviorImpact }
        let boundaryNeeds = groundedRelations.filter { $0.kind == .boundaryNeed }
        let controllableParts = groundedRelations.filter { $0.kind == .controllablePart }
        let capacityConditions = groundedRelations.filter { $0.kind == .conditionCapacity }
        let selfEvaluations = groundedRelations.filter { $0.kind == .selfEvaluation }
        let unmetNeeds = groundedRelations.filter { $0.kind == .unmetNeed }

        if behaviorImpacts.contains(where: {
            !Set($0.concepts).isDisjoint(
                with: Set<SemanticConcept>([.repair, .responsibility, .communication])
            )
        }) {
            return .repair
        }
        if !boundaryNeeds.isEmpty {
            return .protection
        }

        let currentBurdenIsHigh =
            analysis.distressLevel >= 2 ||
            analysis.selfAttackLevel >= 2 ||
            analysis.reflectiveCapacity <= 1
        let tenderSupportIsGrounded =
            !capacityConditions.isEmpty ||
            !selfEvaluations.isEmpty ||
            !unmetNeeds.isEmpty
        if currentBurdenIsHigh && tenderSupportIsGrounded {
            return .care
        }
        if !controllableParts.isEmpty || !behaviorImpacts.isEmpty {
            return .change
        }
        // No repair/change evidence does not mean that no practice is possible. When the
        // transcript still contains an evidence-backed burden, whole-self judgment, or unmet
        // need, a low-demand care practice is the non-blaming direction.
        if tenderSupportIsGrounded {
            return .care
        }
        return .noAction
    }
}

actor SessionStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("ReflectionSessions", isDirectory: true)
    }
    func save(_ session: ReflectionSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: directory.appendingPathComponent("\(session.id.uuidString).json"), options: .atomic)
    }
    func load(id: UUID) throws -> ReflectionSession? {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            ReflectionSession.self,
            from: Data(contentsOf: url)
        )
    }
    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

struct TrackingSourceCandidate: Equatable {
    let bundleIdentifier: String
    let distinctDayCount: Int
    let sampleCount: Int
}

struct HealthSourcePriorityPolicy {
    func preferredBundleIdentifier(from candidates: [TrackingSourceCandidate]) -> String? {
        candidates.max { lhs, rhs in
            if lhs.distinctDayCount != rhs.distinctDayCount {
                return lhs.distinctDayCount < rhs.distinctDayCount
            }
            if lhs.sampleCount != rhs.sampleCount { return lhs.sampleCount < rhs.sampleCount }
            return lhs.bundleIdentifier > rhs.bundleIdentifier
        }?.bundleIdentifier
    }
}

actor HealthKitService {
    private let store = HKHealthStore()
    private let analyzer = DeterministicSelfTrackingAnalyzer()
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeart = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        try? await store.requestAuthorization(toShare: [], read: [sleep, restingHeart, hrv, steps])
    }

    func fetch(referenceDate: Date) async -> [TrackingCue] {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let restingHeart = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
              let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [] }
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let recentStart = calendar.date(byAdding: .day, value: -6, to: referenceDay) ?? referenceDay
        let rangeStart = calendar.date(byAdding: .day, value: -34, to: referenceDay) ?? recentStart
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: referenceDay) ?? referenceDate
        async let sleepSamples = samples(type: sleep, start: rangeStart, end: rangeEnd)
        async let heartSamples = samples(type: restingHeart, start: rangeStart, end: rangeEnd)
        async let hrvSamples = samples(type: hrv, start: rangeStart, end: rangeEnd)
        async let stepSamples = samples(type: steps, start: rangeStart, end: rangeEnd)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let sleeps = preferredSourceSamples(
            await sleepSamples.compactMap { $0 as? HKCategorySample }.filter { asleepValues.contains($0.value) }
        )
        let hearts = preferredSourceSamples(await heartSamples.compactMap { $0 as? HKQuantitySample })
        let hrvs = preferredSourceSamples(await hrvSamples.compactMap { $0 as? HKQuantitySample })
        let stepValues = preferredSourceSamples(await stepSamples.compactMap { $0 as? HKQuantitySample })
        let historyDays = (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: rangeStart) }
        var cues: [TrackingCue] = []
        var dataset = SelfTrackingDataset(dailyMetrics: [:], provenance: [:])

        let sleepGroups = Dictionary(grouping: sleeps) { calendar.startOfDay(for: $0.endDate) }
        let nightlyHistory = historyDays.map { day -> TrackingDataPoint in
            let night = sleepGroups[day] ?? []
            let hours = night.isEmpty ? nil : mergedDuration(of: night) / 3600
            return .init(date: day, value: hours, count: night.count)
        }
        let sleepTimingHistory = historyDays.map { day -> TrackingDataPoint in
            let night = sleepGroups[day] ?? []
            guard let onset = night.map(\.startDate).min() else {
                return .init(date: day, value: nil, count: 0)
            }
            // Store the first asleep interval rather than the sleep midpoint. This produces a
            // user-understandable “usual time of falling asleep” while the analyzer still handles
            // midnight with circular comparisons.
            let components = calendar.dateComponents([.hour, .minute], from: onset)
            let decimalHour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            return .init(date: day, value: decimalHour, count: night.count)
        }
        let sleepWakeHistory = historyDays.map { day -> TrackingDataPoint in
            let night = sleepGroups[day] ?? []
            guard let wake = night.map(\.endDate).max() else {
                return .init(date: day, value: nil, count: 0)
            }
            let components = calendar.dateComponents([.hour, .minute], from: wake)
            let decimalHour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
            return .init(date: day, value: decimalHour, count: night.count)
        }
        let sleepContinuityHistory = historyDays.map { day -> TrackingDataPoint in
            let night = sleepGroups[day] ?? []
            guard let onset = night.map(\.startDate).min(),
                  let wake = night.map(\.endDate).max() else {
                return .init(date: day, value: nil, count: 0)
            }
            let elapsed = wake.timeIntervalSince(onset)
            guard elapsed > 0 else { return .init(date: day, value: nil, count: night.count) }
            // This is deliberately a record-continuity proxy: asleep intervals divided by their
            // first-to-last span. It is not a subjective sleep-quality score.
            return .init(
                date: day,
                value: min(max(mergedDuration(of: night) / elapsed, 0), 1),
                count: night.count
            )
        }
        let nightlyPoints = Array(nightlyHistory.suffix(7))
        let nightlyHours = nightlyPoints.compactMap(\.value)
        if !nightlyHours.isEmpty {
            let medianHours = TrackingStatistics.median(nightlyHours)
            cues.append(.init(
                source: .healthSleep,
                observation: "最近 7 天中有 \(nightlyHours.count) 晚睡眠记录，仍需结合个人历史和缺失记录理解。",
                metrics: .init(
                    periodStart: recentStart,
                    periodEnd: referenceDay,
                    summaryValue: medianHours,
                    unit: "小时/晚",
                    sampleCount: sleeps.count,
                    daily: nightlyPoints
                )
            ))
            dataset.dailyMetrics[.sleepDuration] = nightlyHistory
            dataset.provenance[.sleepDuration] = provenance(for: sleeps, sampleType: "sleepAnalysis")
            dataset.dailyMetrics[.sleepTiming] = sleepTimingHistory
            dataset.provenance[.sleepTiming] = provenance(for: sleeps, sampleType: "sleepAnalysisTiming")
            dataset.dailyMetrics[.sleepWakeTime] = sleepWakeHistory
            dataset.provenance[.sleepWakeTime] = provenance(for: sleeps, sampleType: "sleepAnalysisWakeTime")
            dataset.dailyMetrics[.sleepContinuity] = sleepContinuityHistory
            dataset.provenance[.sleepContinuity] = provenance(for: sleeps, sampleType: "sleepAnalysisRecordedContinuity")
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        if let cue = quantityCue(
            source: .healthHeartRate,
            label: "最近 7 天静息心率",
            samples: hearts,
            unit: bpm,
            suffix: "bpm",
            days: historyDays,
            periodStart: recentStart,
            periodEnd: referenceDay
        ) {
            dataset.dailyMetrics[.restingHeartRate] = cue.metrics?.daily
            dataset.provenance[.restingHeartRate] = provenance(for: hearts, sampleType: "restingHeartRate")
            var recentCue = cue
            if let metrics = cue.metrics {
                recentCue.metrics = .init(
                    periodStart: recentStart, periodEnd: referenceDay,
                    summaryValue: TrackingStatistics.median(Array(metrics.daily.suffix(7)).compactMap(\.value)),
                    unit: metrics.unit, sampleCount: hearts.count, daily: Array(metrics.daily.suffix(7))
                )
            }
            cues.append(recentCue)
        }
        let milliseconds = HKUnit.secondUnit(with: .milli)
        if let cue = quantityCue(
            source: .healthHRV,
            label: "最近 7 天 HRV（SDNN）",
            samples: hrvs,
            unit: milliseconds,
            suffix: "ms",
            days: historyDays,
            periodStart: recentStart,
            periodEnd: referenceDay
        ) {
            dataset.dailyMetrics[.heartRateVariability] = cue.metrics?.daily
            dataset.provenance[.heartRateVariability] = provenance(for: hrvs, sampleType: "heartRateVariabilitySDNN")
            var recentCue = cue
            if let metrics = cue.metrics {
                recentCue.metrics = .init(
                    periodStart: recentStart, periodEnd: referenceDay,
                    summaryValue: TrackingStatistics.median(Array(metrics.daily.suffix(7)).compactMap(\.value)),
                    unit: metrics.unit, sampleCount: hrvs.count, daily: Array(metrics.daily.suffix(7))
                )
            }
            cues.append(recentCue)
        }
        let stepUnit = HKUnit.count()
        if let cue = quantityCue(
            source: .healthSteps,
            label: "最近 7 天步数记录",
            samples: stepValues,
            unit: stepUnit,
            suffix: "步",
            days: historyDays,
            periodStart: recentStart,
            periodEnd: referenceDay,
            aggregation: .sum
        ) {
            dataset.dailyMetrics[.steps] = cue.metrics?.daily
            dataset.provenance[.steps] = provenance(for: stepValues, sampleType: "stepCount")
            var recentCue = cue
            if let metrics = cue.metrics {
                recentCue.metrics = .init(
                    periodStart: recentStart, periodEnd: referenceDay,
                    summaryValue: TrackingStatistics.median(Array(metrics.daily.suffix(7)).compactMap(\.value)),
                    unit: metrics.unit, sampleCount: stepValues.count, daily: Array(metrics.daily.suffix(7))
                )
            }
            cues.append(recentCue)
        }
        if let analysis = try? await analyzer.analyze(eventDate: referenceDate, availableData: dataset) {
            let sleepDetailMetrics: Set<TrackingMetric> = [.sleepTiming, .sleepWakeTime, .sleepContinuity]
            for insight in analysis.insights where sleepDetailMetrics.contains(insight.metric) {
                cues.append(TrackingCue(
                    source: .healthSleep,
                    observation: insight.neutralObservation,
                    metrics: nil,
                    insight: insight
                ))
            }
            for index in cues.indices where cues[index].insight == nil {
                let metric: TrackingMetric = switch cues[index].source {
                case .healthSleep: .sleepDuration
                case .healthHeartRate: .restingHeartRate
                case .healthHRV: .heartRateVariability
                case .healthSteps: .steps
                case .calendarLoad: .calendarLoad
                }
                if let insight = analysis.insights.first(where: { $0.metric == metric }) {
                    cues[index].insight = insight
                    cues[index] = TrackingCue(
                        id: cues[index].id,
                        source: cues[index].source,
                        observation: insight.neutralObservation,
                        included: false,
                        metrics: cues[index].metrics,
                        insight: insight
                    )
                }
            }
            if let sleepIndex = cues.firstIndex(where: { $0.source == .healthSleep && $0.metrics != nil }),
               let durationInsight = cues[sleepIndex].insight {
                let detailInsights = analysis.insights.filter { $0.metric.isSleepNightMetric }
                cues[sleepIndex] = TrackingCue(
                    id: cues[sleepIndex].id,
                    source: .healthSleep,
                    observation: sleepContextObservation(
                        durationInsight: durationInsight,
                        detailInsights: detailInsights
                    ),
                    metrics: cues[sleepIndex].metrics,
                    insight: durationInsight
                )
            }
        }
        return cues
    }

    private func samples(type: HKSampleType, start: Date, end: Date) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private func quantityCue(
        source: TrackingSource,
        label: String,
        samples: [HKQuantitySample],
        unit: HKUnit,
        suffix: String,
        days: [Date],
        periodStart: Date,
        periodEnd: Date,
        aggregation: QuantityAggregation = .average
    ) -> TrackingCue? {
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return nil }
        let average = TrackingStatistics.median(values)
        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.startDate) }
        let daily = days.map { day -> TrackingDataPoint in
            let samples = groups[day] ?? []
            let values = samples.map { $0.quantity.doubleValue(for: unit) }
            let dailyAverage: Double?
            if values.isEmpty {
                dailyAverage = nil
            } else {
                switch aggregation {
                case .average:
                    dailyAverage = TrackingStatistics.median(values)
                case .sum:
                    dailyAverage = values.reduce(0, +)
                }
            }
            return .init(date: day, value: dailyAverage, count: samples.count)
        }
        return .init(
            source: source,
            observation: "\(label)中有 \(daily.filter { $0.value != nil }.count) 天可用记录，记录本身不能说明原因。",
            metrics: .init(
                periodStart: periodStart,
                periodEnd: periodEnd,
                summaryValue: average,
                unit: suffix,
                sampleCount: values.count,
                daily: daily
            )
        )
    }

    private enum QuantityAggregation { case average, sum }

    /// Select one source deterministically before aggregation. The source with the most
    /// distinct recorded days wins; ties use sample count and bundle identifier. This prevents
    /// duplicate records from multiple devices from being silently added together.
    private func preferredSourceSamples<T: HKSample>(_ samples: [T]) -> [T] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        let candidates = groups.map { bundle, values in
            TrackingSourceCandidate(
                bundleIdentifier: bundle,
                distinctDayCount: Set(values.map { calendar.startOfDay(for: $0.startDate) }).count,
                sampleCount: values.count
            )
        }
        guard let preferred = HealthSourcePriorityPolicy().preferredBundleIdentifier(from: candidates) else {
            return []
        }
        return groups[preferred] ?? []
    }

    private func provenance<T: HKSample>(for samples: [T], sampleType: String) -> [TrackingProvenance] {
        Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
            .map { bundle, values in
                let first = values.first
                return TrackingProvenance(
                    sampleType: sampleType,
                    sourceName: first?.sourceRevision.source.name,
                    sourceBundleIdentifier: bundle,
                    sourceVersion: first?.sourceRevision.version,
                    deviceName: first?.device?.name,
                    startDate: values.map(\.startDate).min(),
                    endDate: values.map(\.endDate).max(),
                    timeZoneIdentifier: TimeZone.current.identifier,
                    sampleCount: values.count,
                    authorizationStatus: "read request completed; HealthKit does not disclose read denial per type"
                )
            }
            .sorted { ($0.sourceBundleIdentifier ?? "") < ($1.sourceBundleIdentifier ?? "") }
    }

    /// HealthKit can contain overlapping sleep records from multiple devices or
    /// sleep stages. Merge intervals so the visualized duration is not doubled.
    private func mergedDuration(of samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return max(0, total)
    }

    private func sleepContextObservation(
        durationInsight: TrackingInsight,
        detailInsights: [TrackingInsight]
    ) -> String {
        let byMetric = Dictionary(uniqueKeysWithValues: detailInsights.map { ($0.metric, $0) })
        var parts: [String] = []
        if let duration = durationInsight.recentMedian {
            var item = "时长中位数约 \(String(format: "%.1f", duration)) 小时"
            if let difference = durationInsight.absoluteDifference {
                let minutes = Int((abs(difference) * 60).rounded())
                item += "（比个人近期水平约 \(minutes) 分钟\(difference >= 0 ? "更多" : "更少")"
            }
            parts.append(item)
        }
        if let onset = byMetric[.sleepTiming]?.recentMedian {
            var item = "入睡约 \(clockTime(onset))"
            if let difference = byMetric[.sleepTiming]?.absoluteDifference {
                item += "（约 \(Int((abs(difference) * 60).rounded())) 分钟\(difference >= 0 ? "更晚" : "更早")）"
            }
            parts.append(item)
        }
        if let wake = byMetric[.sleepWakeTime]?.recentMedian {
            var item = "醒来约 \(clockTime(wake))"
            if let difference = byMetric[.sleepWakeTime]?.absoluteDifference {
                item += "（约 \(Int((abs(difference) * 60).rounded())) 分钟\(difference >= 0 ? "更晚" : "更早")）"
            }
            parts.append(item)
        }
        if let continuity = byMetric[.sleepContinuity]?.recentMedian {
            var item = "已记录睡眠区间连续程度约 \(Int((continuity * 100).rounded()))%"
            if let difference = byMetric[.sleepContinuity]?.absoluteDifference {
                item += "（约 \(Int((abs(difference) * 100).rounded())) 个百分点\(difference >= 0 ? "更高" : "更低")）"
            }
            parts.append(item)
        }
        let coverage = durationInsight.coverageDescription
        let measurements = parts.isEmpty ? "记录不足以形成睡眠作息描述" : parts.joined(separator: "；")
        return "最近 \(coverage)：\(measurements)。这些记录共同描述作息和设备记录到的睡眠连续程度，不等同于主观睡眠质量，也不能说明情绪、原因或责任。"
    }

    private func clockTime(_ decimalHour: Double) -> String {
        let normalized = ((decimalHour.truncatingRemainder(dividingBy: 24)) + 24)
            .truncatingRemainder(dividingBy: 24)
        let minutes = Int((normalized * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

actor CalendarService {
    private let store = EKEventStore()
    private let analyzer = DeterministicSelfTrackingAnalyzer()
    func requestAuthorization() async { _ = try? await store.requestFullAccessToEvents() }

    func accessMessage() -> String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: "日历已获得完整读取权限。"
        case .writeOnly: "日历目前只有写入权限，无法读取日程。"
        case .denied: "日历读取权限已被拒绝，请到系统设置中允许。"
        case .restricted: "该设备限制了日历读取。"
        case .notDetermined: "日历读取权限尚未确认。"
        @unknown default: "日历权限状态无法确认。"
        }
    }

    func fetch(referenceDate: Date) async -> [TrackingCue] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let recentStart = calendar.date(byAdding: .day, value: -6, to: referenceDay) ?? referenceDay
        let start = calendar.date(byAdding: .day, value: -34, to: referenceDay) ?? recentStart
        let end = calendar.date(byAdding: .day, value: 1, to: referenceDay) ?? referenceDate
        let items = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        let timedItems = items.filter { !$0.isAllDay }
        // An entirely empty timed calendar is an absence of a usable contextual signal, not a
        // 35-day series of evidence about the person's workload. Returning no cue here prevents
        // later dialogue layers—including legacy fallbacks—from turning zero recorded events into
        // a claim that the person has had more things to handle.
        guard !timedItems.isEmpty else { return [] }
        let historyDays = (0..<35).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let dailyHistory = historyDays.map { day -> TrackingDataPoint in
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let overlapping = items.filter { $0.startDate < dayEnd && $0.endDate > day }
            let timed = overlapping.filter { !$0.isAllDay }
            let timedHours = CalendarOccupiedTimeCalculator.occupiedHours(
                intervals: timed.map {
                    DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate))
                },
                within: DateInterval(start: day, end: dayEnd)
            )
            return .init(date: day, value: timedHours, count: timed.count)
        }
        let recentDaily = Array(dailyHistory.suffix(7))
        let recentTimed = timedItems.filter { $0.endDate > recentStart }
        var cue = TrackingCue(
            source: .calendarLoad,
            observation: "最近 7 天中记录到 \(recentTimed.count) 个定时日程；这里只统计去重后的占用时间，不读取标题或内容。",
            metrics: .init(
                periodStart: recentStart,
                periodEnd: referenceDay,
                summaryValue: recentDaily.compactMap(\.value).reduce(0, +),
                unit: "小时",
                sampleCount: recentTimed.count,
                daily: recentDaily
            )
        )
        let provenance = TrackingProvenance(
            sampleType: "calendarEvents",
            sourceName: "EventKit",
            sourceBundleIdentifier: nil,
            sourceVersion: nil,
            deviceName: nil,
            startDate: start,
            endDate: end,
            timeZoneIdentifier: TimeZone.current.identifier,
            sampleCount: timedItems.count,
            authorizationStatus: accessMessage()
        )
        let dataset = SelfTrackingDataset(
            dailyMetrics: [.calendarLoad: dailyHistory],
            provenance: [.calendarLoad: [provenance]]
        )
        if let analysis = try? await analyzer.analyze(eventDate: referenceDate, availableData: dataset),
           let insight = analysis.insights.first {
            cue.insight = insight
            cue = TrackingCue(
                id: cue.id,
                source: .calendarLoad,
                observation: insight.neutralObservation,
                metrics: cue.metrics,
                insight: insight
            )
        }
        return [cue]
    }
}
