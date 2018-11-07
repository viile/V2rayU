//
//  V2rayConfig.swift
//  V2rayU
//
//  Created by yanue on 2018/10/25.
//  Copyright © 2018 yanue. All rights reserved.
//

import Foundation
import SwiftyJSON
import JavaScriptCore

let jsSourceFormatConfig =
        """
        /**
         * V2ray Config Format
         * @return {string}
         */
        var V2rayConfigFormat = function (encodeStr) {
            var deStr = decodeURIComponent(encodeStr);
            if (!deStr) {
                return "error: cannot decode uri"
            }
        
            try {
                var obj = JSON.parse(deStr);
                if (!obj) {
                    return "error: cannot parse json"
                }
        
                var v2rayConfig = {};
                // ordered keys
                v2rayConfig["log"] = obj.log;
                v2rayConfig["inbounds"] = obj.inbounds;
                v2rayConfig["inbound"] = obj.inbound;
                v2rayConfig["inboundDetour"] = obj.inboundDetour;
                v2rayConfig["outbounds"] = obj.outbounds;
                v2rayConfig["outbound"] = obj.outbound;
                v2rayConfig["outboundDetour"] = obj.outboundDetour;
                v2rayConfig["api"] = obj.api;
                v2rayConfig["dns"] = obj.dns;
                v2rayConfig["stats"] = obj.stats;
                v2rayConfig["routing"] = obj.routing;
                v2rayConfig["policy"] = obj.policy;
                v2rayConfig["reverse"] = obj.reverse;
                v2rayConfig["transport"] = obj.transport;
                
                return JSON.stringify(v2rayConfig, null, 2);
            } catch (e) {
                console.log("error", e);
                return "error: " + e.toString()
            }
        };
        """

class V2rayConfig: NSObject {
    var v2ray: V2rayStruct = V2rayStruct()
    var isValid = false

    // base
    var httpPort = ""
    var socksPort = ""
    var ennableUdp = true
    var ennableMux = true
    var mux = 8
    var dns = ""

    // server
    var serverProtocol = V2rayProtocolOutbound.vmess.rawValue
    var serverVmess = V2rayOutboundVMessItem()
    var serverSocks5 = V2rayOutboundSocks()
    var serverShadowsocks = V2rayOutboundShadowsockServer()

    // transfor
    var streamNetwork = V2rayStreamSettings.network.tcp.rawValue
    var streamTcp = TcpSettings()
    var streamKcp = KcpSettings()
    var streamDs = DsSettings()
    var streamWs = WsSettings()
    var streamH2 = HttpSettings()

    // tls
    var streamTlsSecurity = "none"
    var streamTlsAllowInsecure = true
    var streamTlsServerName = ""

    private var foundHttpPort = false
    private var foundSockPort = false
    private var foundServerProtocol = false

    // combine manual edited data
    // by manual tab view
    func combineManual() -> String {

        if self.isValid {
            // replace

        } else {
            // add
            self.v2ray = V2rayStruct()
        }

        // 1. encode to json text
        let encoder = JSONEncoder()
        let data = try! encoder.encode(self.v2ray)
        var jsonStr = String(data: data, encoding: .utf8)!

        // 2. format json text by javascript
        if let context = JSContext() {
            context.evaluateScript(jsSourceFormatConfig)
            // call js func
            if let formatFunction = context.objectForKeyedSubscript("V2rayConfigFormat"),
               let escapedString = jsonStr.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                if let result = formatFunction.call(withArguments: [escapedString]) {
                    // error occurred with prefix "error:"
                    if let reStr = result.toString(), reStr.count > 0 && !reStr.hasPrefix("error:") {
                        // replace json str
                        jsonStr = reStr
                    }
                }
            }
        }

        return jsonStr
    }

    func combineManualData() {

    }

    // parse imported or edited json text
    // by import tab view
    func parseJson(jsonText: String) -> String {
        guard var json = try? JSON(data: jsonText.data(using: String.Encoding.utf8, allowLossyConversion: false)!) else {
            return "invalid json"
        }

        if !json.exists() {
            return "invalid json"
        }

        // get dns data
        if json["dns"].dictionaryValue.count > 0 {
            let dnsServers = json["dns"]["servers"].array?.compactMap({ $0.string })
            if ((dnsServers?.count) != nil) {
                self.v2ray.dns?.servers = dnsServers
                self.dns = dnsServers!.joined(separator: ",")
            }
        }

        // ============ parse inbound start =========================================
        // > 4.0
        if json["inbounds"].exists() {
            // check inbounds
            if json["inbounds"].arrayValue.count == 0 {
                return "missing inbounds"
            }

            json["inbounds"].arrayValue.forEach { val in
                let (v2rayInbound, errmsg) = self.parseInbound(jsonParams: val)
                if errmsg != "" {
                    print("errmsg", errmsg)
                    return
                }

                // set into v2ray
                self.v2ray.inbounds?.append(v2rayInbound)
            }
        } else {
            // old version
            // 1. inbound
            if json["inbound"].dictionaryValue.count == 0 {
                return "missing inbound"
            }

            let (v2rayInbound, errmsg) = self.parseInbound(jsonParams: json["inbound"])
            if errmsg != "" {
                return errmsg
            }

            self.v2ray.inbound = v2rayInbound

            // 2. inboundDetour
            json["inboundDetour"].arrayValue.forEach { val in
                let (v2rayInbound, errmsg) = self.parseInbound(jsonParams: val)
                if errmsg != "" {
                    print("errmsg", errmsg)
                    return
                }

                // set into v2ray
                self.v2ray.inboundDetour?.append(v2rayInbound)
            }
        }
        // ------------ parse inbound end -------------------------------------------

        // ============ parse outbound start =========================================
        // > 4.0
        if json["outbounds"].exists() {
            // check outbounds
            if json["outbounds"].arrayValue.count == 0 {
                return "missing outbounds"
            }

            // outbounds
            json["outbounds"].arrayValue.forEach { val in
                let (v2rayOutbound, errmsg) = self.parseOutbound(jsonParams: val)
                if errmsg != "" {
                    print("errmsg", errmsg)
                    return
                }

                // set into v2ray
                self.v2ray.outbounds?.append(v2rayOutbound)
            }
        } else {
            // check outbounds
            // 1. outbound
            if json["outbound"].dictionaryValue.count == 0 {
                return "missing outbound"
            }

            let (v2rayOutbound, errmsg) = self.parseOutbound(jsonParams: json["outbound"])
            if errmsg != "" {
                return errmsg
            }

            self.v2ray.outbound = v2rayOutbound

            // outboundDetour
            json["outboundDetour"].arrayValue.forEach { val in
                let (v2rayOutbound, errmsg) = self.parseOutbound(jsonParams: val)
                if errmsg != "" {
                    print("errmsg", errmsg)
                    return
                }

                // set into v2ray
                self.v2ray.outboundDetour?.append(v2rayOutbound)
            }
        }
        // ------------ parse outbound end -------------------------------------------

        if json["routing"].dictionaryValue.count > 0 {
//            return "missing routing"
        }

        v2ray.transport = self.parseTransport(steamJson: json["transport"])
        self.isValid = true

        return ""
    }

    // parse inbound from json
    func parseInbound(jsonParams: JSON) -> (V2rayInbound, String) {
        var v2rayInbound = V2rayInbound()

        if !jsonParams["protocol"].exists() {
            return (v2rayInbound, "missing inbound.protocol")
        }

        if (V2rayProtocolInbound(rawValue: jsonParams["protocol"].stringValue) == nil) {
            return (v2rayInbound, "invalid inbound.protocol")
        }

        // set protocol
        v2rayInbound.protocol = V2rayProtocolInbound(rawValue: jsonParams["protocol"].stringValue)!

        if !jsonParams["port"].exists() {
            return (v2rayInbound, "missing inbound.port")
        }

        if !(jsonParams["port"].intValue > 1024 && jsonParams["port"].intValue < 65535) {
            return (v2rayInbound, "invalid inbound.port")
        }

        // set port
        v2rayInbound.port = String(jsonParams["port"].intValue)

        if jsonParams["listen"].stringValue.count > 0 {
            // set listen
            v2rayInbound.listen = jsonParams["listen"].stringValue
        }

        if jsonParams["tag"].stringValue.count > 0 {
            // set tag
            v2rayInbound.tag = jsonParams["tag"].stringValue
        }

        // settings depends on protocol
        if jsonParams["settings"].dictionaryValue.count > 0 {

            switch v2rayInbound.protocol {

            case .http:
                var settings = V2rayInboundHttp()

                if jsonParams["settings"]["timeout"].dictionaryValue.count > 0 {
                    settings.timeout = jsonParams["settings"]["timeout"].intValue
                }

                if jsonParams["settings"]["allowTransparent"].dictionaryValue.count > 0 {
                    settings.allowTransparent = jsonParams["settings"]["allowTransparent"].boolValue
                }

                if jsonParams["settings"]["userLevel"].dictionaryValue.count > 0 {
                    settings.userLevel = jsonParams["settings"]["userLevel"].intValue
                }
                // accounts
                if jsonParams["settings"]["accounts"].dictionaryValue.count > 0 {
                    var accounts: [V2rayInboundHttpAccount] = []
                    for subJson in jsonParams["settings"]["accounts"].arrayValue {
                        var account = V2rayInboundHttpAccount()
                        account.user = subJson["user"].stringValue
                        account.pass = subJson["pass"].stringValue
                        accounts.append(account)
                    }
                    settings.accounts = accounts
                }
                // set into inbound
                v2rayInbound.settingHttp = settings
                break

            case .shadowsocks:
                var settings = V2rayInboundShadowsocks()
                settings.email = jsonParams["settings"]["timeout"].stringValue
                settings.password = jsonParams["settings"]["password"].stringValue
                settings.method = jsonParams["settings"]["method"].stringValue
                settings.udp = jsonParams["settings"]["udp"].boolValue
                settings.level = jsonParams["settings"]["level"].intValue
                settings.ota = jsonParams["settings"]["ota"].boolValue

                // set into inbound
                v2rayInbound.settingShadowsocks = settings
                break

            case .socks:
                var settings = V2rayInboundSocks()
                settings.auth = jsonParams["settings"]["auth"].stringValue
                // accounts
                if jsonParams["settings"]["accounts"].dictionaryValue.count > 0 {
                    var accounts: [V2rayInboundSockAccount] = []
                    for subJson in jsonParams["settings"]["accounts"].arrayValue {
                        var account = V2rayInboundSockAccount()
                        account.user = subJson["user"].stringValue
                        account.pass = subJson["pass"].stringValue
                        accounts.append(account)
                    }
                    settings.accounts = accounts
                }

                settings.udp = jsonParams["settings"]["udp"].boolValue
                settings.ip = jsonParams["settings"]["ip"].stringValue
                settings.timeout = jsonParams["settings"]["timeout"].intValue
                settings.userLevel = jsonParams["settings"]["userLevel"].intValue

                // set into inbound
                v2rayInbound.settingSocks = settings
                break

            case .vmess:
                var settings = V2rayInboundVMess()
                settings.disableInsecureEncryption = jsonParams["settings"]["disableInsecureEncryption"].boolValue
                // clients
                if jsonParams["settings"]["clients"].dictionaryValue.count > 0 {
                    var clients: [V2RayInboundVMessClient] = []
                    for subJson in jsonParams["settings"]["clients"].arrayValue {
                        var client = V2RayInboundVMessClient()
                        client.id = subJson["id"].stringValue
                        client.level = subJson["level"].intValue
                        client.alterId = subJson["alterId"].intValue
                        client.email = subJson["email"].stringValue
                        clients.append(client)
                    }
                    settings.clients = clients
                }

                if jsonParams["settings"]["default"].dictionaryValue.count > 0 {
                    settings.`default`?.level = jsonParams["settings"]["default"]["level"].intValue
                    settings.`default`?.alterId = jsonParams["settings"]["default"]["alterId"].intValue
                }

                if jsonParams["settings"]["detour"].dictionaryValue.count > 0 {
                    var detour = V2RayInboundVMessDetour()
                    detour.to = jsonParams["settings"]["detour"]["to"].stringValue
                    settings.detour = detour
                }

                // set into inbound
                v2rayInbound.settingVMess = settings
                break
            }
        }

        // stream settings
        if jsonParams["streamSettings"].dictionaryValue.count > 0 {
            let (errmsg, stream) = self.parseSteamSettings(steamJson: jsonParams["streamSettings"], preTxt: "inbound")
            if errmsg != "" {
                return (v2rayInbound, errmsg)
            }
            v2rayInbound.streamSettings = stream
        }

        // set local socks5 port
        if v2rayInbound.protocol == V2rayProtocolInbound.socks && !self.foundSockPort {
            self.socksPort = v2rayInbound.port
            self.foundSockPort = true
        }

        // set local http port
        if v2rayInbound.protocol == V2rayProtocolInbound.http && !self.foundHttpPort {
            self.httpPort = v2rayInbound.port
            self.foundHttpPort = true
        }

        return (v2rayInbound, "")
    }

    // parse outbound from json
    func parseOutbound(jsonParams: JSON) -> (V2rayOutbound, String) {
        var v2rayOutbound = V2rayOutbound()

        if !(jsonParams["protocol"].exists()) {
            return (v2rayOutbound, "missing outbound.protocol")
        }

        if (V2rayProtocolOutbound(rawValue: jsonParams["protocol"].stringValue) == nil) {
            return (v2rayOutbound, "invalid outbound.protocol")
        }
        // set protocol
        v2rayOutbound.protocol = V2rayProtocolOutbound(rawValue: jsonParams["protocol"].stringValue)!

        v2rayOutbound.sendThrough = jsonParams["sendThrough"].stringValue
        v2rayOutbound.tag = jsonParams["tag"].stringValue

        if jsonParams["mux"].dictionaryValue.count > 0 {
            var mux = V2rayOutboundMux()
            mux.enabled = jsonParams["mux"]["enabled"].boolValue
            mux.concurrency = jsonParams["mux"]["concurrency"].intValue
            v2rayOutbound.mux = mux
            self.ennableMux = mux.enabled
            self.mux = mux.concurrency
        }

        // settings depends on protocol
        if jsonParams["settings"].dictionaryValue.count > 0 {
            switch v2rayOutbound.protocol {
            case .blackhole:
                var settingBlackhole = V2rayOutboundBlackhole()
                settingBlackhole.response.type = jsonParams["settings"]["response"]["type"].stringValue
                // set into outbound
                v2rayOutbound.settingBlackhole = settingBlackhole
                break

            case .freedom:
                var settingFreedom = V2rayOutboundFreedom()
                settingFreedom.domainStrategy = jsonParams["settings"]["domainStrategy"].stringValue
                settingFreedom.userLevel = jsonParams["settings"]["userLevel"].intValue
                settingFreedom.redirect = jsonParams["settings"]["redirect"].stringValue
                // set into outbound
                v2rayOutbound.settingFreedom = settingFreedom
                break

            case .shadowsocks:
                var settingShadowsocks = V2rayOutboundShadowsocks()
                var servers: [V2rayOutboundShadowsockServer] = []
                // servers
                jsonParams["settings"]["servers"].arrayValue.forEach { val in
                    var server = V2rayOutboundShadowsockServer()
                    server.port = val["port"].intValue
                    server.email = val["email"].stringValue
                    server.address = val["address"].stringValue
                    server.method = val["method"].stringValue
                    server.password = val["password"].stringValue
                    server.ota = val["ota"].boolValue
                    server.level = val["level"].intValue
                    // append
                    servers.append(server)
                }
                settingShadowsocks.servers = servers
                // set into outbound
                v2rayOutbound.settingShadowsocks = settingShadowsocks
                break

            case .socks:
                var settingSocks = V2rayOutboundSocks()
                settingSocks.address = jsonParams["settings"]["address"].stringValue
                settingSocks.port = jsonParams["settings"]["port"].stringValue

                var users: [V2rayOutboundSockUser] = []
                jsonParams["settings"]["users"].arrayValue.forEach { val in
                    var user = V2rayOutboundSockUser()
                    user.user = val["user"].stringValue
                    user.pass = val["pass"].stringValue
                    user.level = val["level"].intValue
                    // append
                    users.append(user)
                }
                settingSocks.users = users

                // set into outbound
                v2rayOutbound.settingSocks = settingSocks
                break

            case .vmess:
                var settingVMess = V2rayOutboundVMess()
                var vnext: [V2rayOutboundVMessItem] = []

                jsonParams["settings"]["vnext"].arrayValue.forEach { val in
                    var item = V2rayOutboundVMessItem()

                    item.address = val["address"].stringValue
                    item.port = val["port"].stringValue

                    var users: [V2rayOutboundVMessUser] = []
                    val["users"].arrayValue.forEach { val in
                        var user = V2rayOutboundVMessUser()
                        user.id = val["id"].stringValue
                        user.alterId = val["alterId"].intValue
                        user.level = val["level"].intValue
                        user.security = val["security"].stringValue
                        users.append(user)
                    }
                    item.users = users
                    // append
                    vnext.append(item)
                }

                settingVMess.vnext = vnext

                // set into outbound
                v2rayOutbound.settingVMess = settingVMess
                break
            }
        }

        // stream settings
        if jsonParams["streamSettings"].dictionaryValue.count > 0 {
            let (errmsg, stream) = self.parseSteamSettings(steamJson: jsonParams["streamSettings"], preTxt: "outbound")
            if errmsg != "" {
                return (v2rayOutbound, errmsg)
            }
            v2rayOutbound.streamSettings = stream
        }

        // set main server protocol
        if !self.foundServerProtocol && [V2rayProtocolOutbound.socks.rawValue, V2rayProtocolOutbound.vmess.rawValue, V2rayProtocolOutbound.shadowsocks.rawValue].contains(v2rayOutbound.protocol.rawValue) {
            self.serverProtocol = v2rayOutbound.protocol.rawValue
            self.foundServerProtocol = true
        }

        if v2rayOutbound.protocol == V2rayProtocolOutbound.socks {
            self.serverSocks5 = v2rayOutbound.settingSocks!
        }

        if v2rayOutbound.protocol == V2rayProtocolOutbound.vmess && v2rayOutbound.settingVMess != nil && v2rayOutbound.settingVMess!.vnext.count > 0 {
            self.serverVmess = v2rayOutbound.settingVMess!.vnext[0]
        }

        if v2rayOutbound.protocol == V2rayProtocolOutbound.shadowsocks && v2rayOutbound.settingShadowsocks != nil && v2rayOutbound.settingShadowsocks!.servers.count > 0 {
            self.serverShadowsocks = v2rayOutbound.settingShadowsocks!.servers[0]
        }

        return (v2rayOutbound, "")
    }

    // parse steamSettings
    func parseSteamSettings(steamJson: JSON, preTxt: String = "") -> (errmsg: String, stream: V2rayStreamSettings) {
        var errmsg = ""
        var stream = V2rayStreamSettings()

        if (V2rayStreamSettings.network(rawValue: steamJson["network"].stringValue) == nil) {
            errmsg = "invalid " + preTxt + ".streamSettings.network"
            return (errmsg: errmsg, stream: stream)
        }
        // set network
        stream.network = V2rayStreamSettings.network(rawValue: steamJson["network"].stringValue)!
        self.streamNetwork = stream.network.rawValue

        if (V2rayStreamSettings.security(rawValue: steamJson["security"].stringValue) == nil) {
            errmsg = "invalid " + preTxt + ".streamSettings.security"
            return (errmsg: errmsg, stream: stream)
        }
        // set security
        stream.security = V2rayStreamSettings.security(rawValue: steamJson["security"].stringValue)!
        self.streamTlsSecurity = stream.security.rawValue

        if steamJson["sockopt"].dictionaryValue.count > 0 {
            var sockopt = V2rayStreamSettingSockopt()

            // tproxy
            if (V2rayStreamSettingSockopt.tproxy(rawValue: steamJson["sockopt"]["tproxy"].stringValue) != nil) {
                sockopt.tproxy = V2rayStreamSettingSockopt.tproxy(rawValue: steamJson["sockopt"]["tproxy"].stringValue)!
            }

            sockopt.tcpFastOpen = steamJson["sockopt"]["tcpFastOpen"].boolValue
            sockopt.mark = steamJson["sockopt"]["mark"].intValue

            stream.sockopt = sockopt
        }

        // steamSettings (same as global transport)
        let transport = self.parseTransport(steamJson: steamJson)
        stream.tlsSettings = transport.tlsSettings
        stream.tcpSettings = transport.tcpSettings
        stream.kcpSettings = transport.kcpSettings
        stream.wsSettings = transport.wsSettings
        stream.httpSettings = transport.httpSettings
        stream.dsSettings = transport.dsSettings

        // for outbound stream
        if preTxt == "outbound" {
            if transport.tlsSettings != nil {
                // set data
                self.streamTlsServerName = transport.tlsSettings!.serverName
                self.streamTlsAllowInsecure = transport.tlsSettings!.allowInsecure
            }

            if transport.tcpSettings != nil {
                self.streamTcp = transport.tcpSettings!
            }

            if transport.kcpSettings != nil {
                self.streamKcp = transport.kcpSettings!
            }

            if transport.wsSettings != nil {
                self.streamWs = transport.wsSettings!
            }

            if transport.httpSettings != nil {
                self.streamH2 = transport.httpSettings!
            }

            if transport.dsSettings != nil {
                self.streamDs = transport.dsSettings!
            }
        }

        return (errmsg: errmsg, stream: stream)
    }

    func parseTransport(steamJson: JSON) -> V2rayTransport {
        var stream = V2rayTransport()
        // tlsSettings
        if steamJson["tlsSettings"].dictionaryValue.count > 0 {
            var tlsSettings = TlsSettings()
            tlsSettings.serverName = steamJson["tlsSettings"]["serverName"].stringValue
            tlsSettings.alpn = steamJson["tlsSettings"]["alpn"].stringValue
            tlsSettings.allowInsecure = steamJson["tlsSettings"]["allowInsecure"].boolValue
            tlsSettings.allowInsecureCiphers = steamJson["tlsSettings"]["allowInsecureCiphers"].boolValue
            // certificates
            if steamJson["tlsSettings"]["certificates"].dictionaryValue.count > 0 {
                var certificates = TlsCertificates()
                let usage = TlsCertificates.usage(rawValue: steamJson["tlsSettings"]["certificates"]["usage"].stringValue)
                if (usage != nil) {
                    certificates.usage = usage!
                }
                certificates.certificateFile = steamJson["tlsSettings"]["certificates"]["certificateFile"].stringValue
                certificates.keyFile = steamJson["tlsSettings"]["certificates"]["keyFile"].stringValue
                certificates.certificate = steamJson["tlsSettings"]["certificates"]["certificate"].stringValue
                certificates.key = steamJson["tlsSettings"]["certificates"]["key"].stringValue
                tlsSettings.certificates = certificates
            }
            stream.tlsSettings = tlsSettings
        }

        // tcpSettings
        if steamJson["tcpSettings"].dictionaryValue.count > 0 {
            var tcpSettings = TcpSettings()
            var tcpHeader = TcpSettingHeader()

            // type
            if steamJson["tcpSettings"]["header"]["type"].stringValue == "http" {
                tcpHeader.type = "http"
            } else {
                tcpHeader.type = "none"
            }

            // request
            if steamJson["tcpSettings"]["header"]["request"].dictionaryValue.count > 0 {
                var requestJson = steamJson["tcpSettings"]["header"]["request"]
                var tcpRequest = TcpSettingHeaderRequest()
                tcpRequest.version = requestJson["version"].stringValue
                tcpRequest.method = requestJson["method"].stringValue
                tcpRequest.path = requestJson["path"].arrayValue.map {
                    $0.stringValue
                }

                if requestJson["headers"].dictionaryValue.count > 0 {
                    var tcpRequestHeaders = TcpSettingHeaderRequestHeaders()
                    tcpRequestHeaders.host = requestJson["headers"]["Host"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.userAgent = requestJson["headers"]["User-Agent"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.acceptEncoding = requestJson["headers"]["Accept-Encoding"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.connection = requestJson["headers"]["Connection"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpRequestHeaders.pragma = requestJson["headers"]["Pragma"].stringValue
                    tcpRequest.headers = tcpRequestHeaders
                }
                tcpHeader.request = tcpRequest
            }

            // response
            if steamJson["tcpSettings"]["header"]["response"].dictionaryValue.count > 0 {
                var responseJson = steamJson["tcpSettings"]["header"]["response"]
                var tcpResponse = TcpSettingHeaderResponse()

                tcpResponse.version = responseJson["version"].stringValue
                tcpResponse.status = responseJson["status"].stringValue

                if responseJson["headers"].dictionaryValue.count > 0 {
                    var tcpResponseHeaders = TcpSettingHeaderResponseHeaders()
                    // contentType, transferEncoding, connection
                    tcpResponseHeaders.contentType = responseJson["headers"]["Content-Type"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.transferEncoding = responseJson["headers"]["Transfer-Encoding"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.connection = responseJson["headers"]["Connection"].arrayValue.map {
                        $0.stringValue
                    }
                    tcpResponseHeaders.pragma = responseJson["headers"]["Pragma"].stringValue
                    tcpResponse.headers = tcpResponseHeaders
                }
                tcpHeader.response = tcpResponse
            }

            tcpSettings.header = tcpHeader

            stream.tcpSettings = tcpSettings
        }

        // kcpSettings see: https://www.v2ray.com/chapter_02/transport/mkcp.html
        if steamJson["kcpSettings"].dictionaryValue.count > 0 {
            var kcpSettings = KcpSettings()
            kcpSettings.mtu = steamJson["kcpSettings"]["mtu"].intValue
            kcpSettings.tti = steamJson["kcpSettings"]["tti"].intValue
            kcpSettings.uplinkCapacity = steamJson["kcpSettings"]["uplinkCapacity"].intValue
            kcpSettings.downlinkCapacity = steamJson["kcpSettings"]["downlinkCapacity"].intValue
            kcpSettings.congestion = steamJson["kcpSettings"]["congestion"].boolValue
            kcpSettings.readBufferSize = steamJson["kcpSettings"]["readBufferSize"].intValue
            kcpSettings.writeBufferSize = steamJson["kcpSettings"]["writeBufferSize"].intValue
            // "none"
            if KcpSettingsHeaderType.firstIndex(of: steamJson["kcpSettings"]["type"].stringValue) != nil {
                kcpSettings.header.type = steamJson["kcpSettings"]["type"].stringValue
            }
            stream.kcpSettings = kcpSettings
        }

        // wsSettings see: https://www.v2ray.com/chapter_02/transport/websocket.html
        if steamJson["wsSettings"].dictionaryValue.count > 0 {
            var wsSettings = WsSettings()
            wsSettings.path = steamJson["wsSettings"]["path"].stringValue
            wsSettings.headers.host = steamJson["wsSettings"]["header"]["host"].stringValue

            stream.wsSettings = wsSettings
        }

        // (HTTP/2)httpSettings see: https://www.v2ray.com/chapter_02/transport/websocket.html
        if steamJson["httpSettings"].dictionaryValue.count > 0 && steamJson["httpSettings"].dictionaryValue.count > 0 {
            var httpSettings = HttpSettings()
            httpSettings.host = steamJson["httpSettings"]["host"].arrayValue.map {
                $0.stringValue
            }
            httpSettings.path = steamJson["httpSettings"]["path"].stringValue

            stream.httpSettings = httpSettings
        }

        // dsSettings
        if steamJson["dsSettings"].dictionaryValue.count > 0 && steamJson["dsSettings"].dictionaryValue.count > 0 {
            var dsSettings = DsSettings()
            dsSettings.path = steamJson["dsSettings"]["path"].stringValue
            stream.dsSettings = dsSettings
        }

        return stream
    }

    // create current v2ray server json file
    static func createJsonFile(item: v2rayItem) {
        let jsonText = item.json

        // path: /Application/V2rayU.app/Contents/Resources/config.json
        guard let jsonFile = V2rayServer.getJsonFile() else {
            NSLog("unable get config file path")
            return
        }

        do {
            let jsonFilePath = URL.init(fileURLWithPath: jsonFile)

            // delete before config
            if FileManager.default.fileExists(atPath: jsonFile) {
                try? FileManager.default.removeItem(at: jsonFilePath)
            }

            try jsonText.write(to: jsonFilePath, atomically: true, encoding: String.Encoding.utf8)
        } catch let error {
            // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
            NSLog("save json file fail: \(error)")
        }
    }
}