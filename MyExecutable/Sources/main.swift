// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import NIO
import NIOPosix
import NIOHTTP1
import PostgresNIO
import Logging

struct CreateUserDTO: Decodable { let name: String }
struct UserDTO: Encodable { let id: Int, name: String }

// ---------- Config ----------
struct AppConfig {
    let httpPort: Int
    let dbHost: String
    let dbPort: Int
    let dbUser: String
    let dbPass: String
    let dbName: String

    static func load() -> AppConfig {
        let env = ProcessInfo.processInfo.environment
        return .init(
            httpPort: Int(env["PORT"] ?? "8081") ?? 8081,
            dbHost:   env["DB_HOST"] ?? "127.0.0.1",
            dbPort:   Int(env["DB_PORT"] ?? "9090") ?? 9090, // seu compose mapeia 9090->5432
            dbUser:   env["DB_USER"] ?? "luccas",
            dbPass:   env["DB_PASS"] ?? "17111998",
            dbName:   env["DB_NAME"] ?? "appdb"
        )
    }
}

final class DB {
    private let group: EventLoopGroup
    private let config: PostgresConnection.Configuration

    init(group: EventLoopGroup, app: AppConfig) {
        self.group = group
        self.config = PostgresConnection.Configuration(
            connection: .init(
                host: app.dbHost,
                port: app.dbPort
            ),
            authentication: .init(username: app.dbUser, database: app.dbName, password: app.dbPass),
            tls: .disable
        )
    }

    func withConnection<T>(on loop: EventLoop,
                           _ body: @escaping (PostgresConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        let logger = Logger(label: "psql")
        let id = Int.random(in: 1...Int.max) // ou um contador atômico, se preferir

        return PostgresConnection.connect(on: loop, configuration: config, id: id, logger: logger)
            .flatMap { conn in
                body(conn)
                    .flatMap { value in
                        conn.close().map { value }                 // sucesso → fecha e propaga valor
                    }
                    .flatMapError { error in
                        conn.close().flatMapThrowing { throw error } // erro → fecha e propaga erro
                    }
            }
    }


}

// ---------- HTTP Handler ----------
final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn  = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let db: DB
    private var head: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer?

    init(db: DB) { self.db = db }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let h):
            head = h
            bodyBuffer = context.channel.allocator.buffer(capacity: 0)
        case .body(var part):
            if var buf = bodyBuffer {
                var p = part; buf.writeBuffer(&p); bodyBuffer = buf
            }
        case .end:
            route(context: context)
            head = nil
            bodyBuffer = nil
        }
    }

    private func route(context: ChannelHandlerContext) {
        guard let head else { return }
        let method = head.method
        let uri = head.uri

        switch (method, uri) {
        case (.GET, "/health"):
            respondJSON(context, status: .ok, body: #"{"status":"ok","time":"\#(ISO8601DateFormatter().string(from: Date()))"}"#)

        case (.GET, "/db/ping"):
            // SELECT 1 => valida conexão
            let fut = db.withConnection(on: context.eventLoop) { conn in
                conn.query("SELECT 1 AS ok", [])
            }.map { rows -> String in
                let ok = rows.first?.column("ok")?.int ?? 0
                return #"{"db":"ok","select":\#(ok)}"#
            }.flatMap { json in
                self.respondJSON(context, status: .ok, body: json)
            }.flatMapError { error in
                self.respondJSON(context, status: .internalServerError, body: #"{"db":"error","message":"\#(error)"}"#)
            }
            _ = fut

        case (.GET, "/users"):
            // Leitura da tabela public.users
            let fut = db.withConnection(on: context.eventLoop) { conn in
                conn.query("SELECT id, name FROM public.users ORDER BY id", [])
            }.map { rows -> String in
                var out = "["
                for (i, r) in rows.enumerated() {
                    let id = r.column("id")?.int ?? 0
                    let name = r.column("name")?.string ?? ""
                    out += #"{"id":\#(id),"name":\#(String(reflecting: name))}"#
                    if i < rows.count - 1 { out += "," }
                }
                out += "]"
                return out
            }.flatMap { json in
                self.respondJSON(context, status: .ok, body: json)
            }.flatMapError { error in
                self.respondJSON(context, status: .internalServerError, body: #"{"error":"\#(error)"}"#)
            }
            _ = fut
        
        // POST /users  -> cria usuário a partir de {"name":"..."}
        case (.POST, "/users"):
            // parse body JSON
            guard var buf = bodyBuffer,
                  let bytes = buf.readBytes(length: buf.readableBytes) else {
                _ = respondJSON(context, status: .badRequest, body: #"{"error":"empty body"}"#)
                return
            }
            do {
                let dto = try JSONDecoder().decode(CreateUserDTO.self, from: Data(bytes))
                guard !dto.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    _ = respondJSON(context, status: .badRequest, body: #"{"error":"name required"}"#)
                    return
                }

                let fut = db.withConnection(on: context.eventLoop) { conn in
                    conn.query(
                        "INSERT INTO public.users (name) VALUES ($1) RETURNING id, name",
                        [PostgresData(string: dto.name)]
                    )
                }
                .flatMap { rows in
                    guard let r = rows.first,
                          let id = r.column("id")?.int,
                          let name = r.column("name")?.string else {
                        return self.respondJSON(context, status: .internalServerError, body: #"{"error":"insert failed"}"#)
                    }
                    let json = #"{"id":\#(id),"name":\#(String(reflecting: name))}"#
                    return self.respondJSON(context, status: .created, body: json)
                }
                .flatMapError { error in
                    self.respondJSON(context, status: .internalServerError, body: #"{"error":"\#(error)"}"#)
                }
                _ = fut
            } catch {
                _ = respondJSON(context, status: .badRequest, body: #"{"error":"invalid json"}"#)
            }

        // GET /users/{id}  -> obtém usuário por ID
        case (.GET, let path) where path.hasPrefix("/users/"):
            let comps = path.split(separator: "/")
            guard comps.count == 2, let id = Int(comps[1]) else {
                _ = respondJSON(context, status: .badRequest, body: #"{"error":"invalid id"}"#)
                return
            }

            let fut = db.withConnection(on: context.eventLoop) { conn in
                conn.query(
                    "SELECT id, name FROM public.users WHERE id = $1 LIMIT 1",
                    [PostgresData(int: id)]
                )
            }
            .flatMap { rows in
                guard let r = rows.first,
                      let uid = r.column("id")?.int,
                      let name = r.column("name")?.string else {
                    return self.respondJSON(context, status: .notFound, body: #"{"error":"not found"}"#)
                }
                let json = #"{"id":\#(uid),"name":\#(String(reflecting: name))}"#
                return self.respondJSON(context, status: .ok, body: json)
            }
            .flatMapError { error in
                self.respondJSON(context, status: .internalServerError, body: #"{"error":"\#(error)"}"#)
            }
            _ = fut

        default:
            respondJSON(context, status: .notFound, body: #"{"error":"not found"}"#)
        }
    }

    private func respondJSON(_ context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) -> EventLoopFuture<Void> {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        headers.add(name: "Cache-Control", value: "no-store")

        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buf = context.channel.allocator.buffer(capacity: body.utf8.count)
        buf.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        return context.writeAndFlush(wrapOutboundOut(.end(nil)))
    }
}

// ---------- Bootstrap ----------
func run() throws {
    let cfg = AppConfig.load()
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    defer { try? group.syncShutdownGracefully() }

    let db = DB(group: group, app: cfg)

    let server = try ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .childChannelInitializer { ch in
            ch.pipeline.configureHTTPServerPipeline().flatMap {
                ch.pipeline.addHandler(HTTPHandler(db: db))
            }
        }
        .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        .bind(host: "0.0.0.0", port: cfg.httpPort)
        .wait()

    print("API up on :\(cfg.httpPort) | DB=\(cfg.dbHost):\(cfg.dbPort)/\(cfg.dbName) user=\(cfg.dbUser)")
    try server.closeFuture.wait()
}

do { try run() } catch { fputs("FATAL: \(error)\n", stderr) }
