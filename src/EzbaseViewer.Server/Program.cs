using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;
using EzbaseViewer.Contracts;
using EzbaseViewer.Core;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<LaunchCodeService>();
builder.Services.AddSingleton<AppTokenService>();
builder.Services.AddSingleton<CompanyDirectory>();
builder.Services.AddSingleton<DeviceDirectory>();
builder.Services.AddSingleton<SessionService>();
builder.Services.AddSingleton<AuditTrail>();
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var app = builder.Build();

app.Use(async (context, next) =>
{
    var correlationId = context.Request.Headers.TryGetValue("X-Correlation-Id", out var supplied) &&
                        !string.IsNullOrWhiteSpace(supplied)
        ? supplied.ToString()
        : Guid.NewGuid().ToString("N");
    context.TraceIdentifier = correlationId;
    context.Response.Headers["X-Correlation-Id"] = correlationId;

    try
    {
        await next();
    }
    catch (DomainException exception)
    {
        context.Response.StatusCode = exception.Code switch
        {
            var code when code.Contains("not_found", StringComparison.Ordinal) => StatusCodes.Status404NotFound,
            "internal_auth_failed" or "private_network_required" => StatusCodes.Status403Forbidden,
            var code when code.EndsWith("_denied", StringComparison.Ordinal) => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest
        };
        await context.Response.WriteAsJsonAsync(new ApiError(exception.Code, exception.Message, correlationId));
    }
});

app.MapGet("/health", () => Results.Ok(new { status = "ok", utc = DateTimeOffset.UtcNow }));

app.MapGet("/v1/system/engine", (HttpContext http) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    return Results.Ok(RemoteEngineSelection.Current);
});

app.MapPost("/v1/launch-codes", (
    HttpContext http,
    LaunchCodeIssueRequest request,
    LaunchCodeService launchCodes,
    AuditTrail audit) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var response = launchCodes.Issue(request, TimeSpan.FromSeconds(60));
    audit.Add("launch_code_issued", request.UserId, request.CompanyId, request.DeviceId, "success", http.TraceIdentifier);
    return Results.Ok(response);
});

app.MapPost("/v1/launch-codes/exchange", (
    HttpContext http,
    LaunchCodeExchangeRequest request,
    LaunchCodeService launchCodes,
    AppTokenService appTokens,
    DeviceDirectory devices,
    AuditTrail audit) =>
{
    var launch = launchCodes.Consume(request.Code);
    var device = devices.Get(launch.DeviceId);
    if (!string.Equals(device.CompanyId, launch.CompanyId, StringComparison.Ordinal))
    {
        throw new DomainException("cross_company_access_denied", "대상 업체의 클라이언트에 접근할 권한이 없습니다.");
    }

    var issued = appTokens.Issue(launch);
    audit.Add("launch_code_exchanged", launch.UserId, launch.CompanyId, launch.DeviceId, "success", http.TraceIdentifier);
    return Results.Ok(new LaunchCodeExchangeResponse(
        issued.Token,
        issued.Context.ExpiresAt,
        device.DeviceId,
        device.DisplayName,
        issued.Context.AllowedCapabilities));
});

app.MapPost("/v1/companies", (
    HttpContext http,
    CompanyCreateRequest request,
    CompanyDirectory companies,
    AuditTrail audit) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var company = companies.Create(request);
    audit.Add("company_created", "system", company.CompanyId, string.Empty, "success", http.TraceIdentifier);
    return Results.Ok(new CompanyResponse(company.CompanyId, company.DisplayName, company.CreatedAt, 0));
});

app.MapGet("/v1/companies", (
    HttpContext http,
    CompanyDirectory companies,
    DeviceDirectory devices) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var response = companies.List()
        .Select(company => new CompanyResponse(
            company.CompanyId,
            company.DisplayName,
            company.CreatedAt,
            devices.ListByCompany(company.CompanyId).Count));
    return Results.Ok(response);
});

app.MapGet("/v1/companies/{companyId}/clients", (
    HttpContext http,
    string companyId,
    DeviceDirectory devices) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var response = devices.ListByCompany(companyId)
        .Select(device => new ManagedClientResponse(
            device.DeviceId,
            device.CompanyId,
            device.DisplayName,
            device.InstallationMode,
            device.AllowUnattendedAccess,
            device.EnrolledAt));
    return Results.Ok(response);
});

app.MapPost("/v1/clients/enrollments", (
    HttpContext http,
    DeviceEnrollmentRequest request,
    DeviceDirectory devices,
    AuditTrail audit) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var device = devices.Enroll(request);
    audit.Add("client_host_enrolled", "system", device.CompanyId, device.DeviceId, "success", http.TraceIdentifier);
    return Results.Ok(new DeviceEnrollmentResponse(
        device.DeviceId,
        device.CompanyId,
        device.InstallationMode,
        device.EnrolledAt));
});

app.MapPost("/v1/sessions", (
    HttpContext http,
    SessionCreateRequest request,
    AppTokenService appTokens,
    SessionService sessions,
    AuditTrail audit) =>
{
    var token = ReadBearerToken(http);
    var caller = appTokens.Validate(token);
    var session = sessions.Create(caller, request);
    audit.Add("session_requested", caller.UserId, caller.CompanyId, session.DeviceId, session.State.ToString(), http.TraceIdentifier);
    return Results.Ok(new SessionCreateResponse(
        session.SessionId,
        session.State,
        session.GrantedCapabilities,
        session.ExpiresAt));
});

app.MapPost("/v1/sessions/{sessionId}/authorize", (
    HttpContext http,
    string sessionId,
    SessionDecisionRequest request,
    SessionService sessions,
    AuditTrail audit) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    var session = sessions.Decide(sessionId, request.Approved);
    audit.Add("session_decided", "host", session.CompanyId, session.DeviceId, session.State.ToString(), http.TraceIdentifier);
    return Results.Ok(new SessionDecisionResponse(session.SessionId, session.State, DateTimeOffset.UtcNow));
});

app.MapGet("/v1/audit-events", (HttpContext http, AuditTrail audit) =>
{
    RequireEzbasePrivateAccess(http, app.Configuration);
    return Results.Ok(audit.ReadAll());
});

app.Run();

static string ReadBearerToken(HttpContext http)
{
    var value = http.Request.Headers.Authorization.ToString();
    const string prefix = "Bearer ";
    if (!value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
    {
        throw new DomainException("app_token_missing", "Bearer 앱 토큰이 필요합니다.");
    }

    return value[prefix.Length..].Trim();
}

static void RequireInternalKey(HttpContext http, IConfiguration configuration)
{
    var expected = configuration["Security:InternalApiKey"] ??
                   Environment.GetEnvironmentVariable("EZBASEVIEWER_INTERNAL_KEY");
    if (string.IsNullOrWhiteSpace(expected))
    {
        throw new InvalidOperationException("Security:InternalApiKey 또는 EZBASEVIEWER_INTERNAL_KEY를 설정해야 합니다.");
    }

    var actual = http.Request.Headers["X-Ezbase-Internal-Key"].ToString();
    var expectedBytes = Encoding.UTF8.GetBytes(expected);
    var actualBytes = Encoding.UTF8.GetBytes(actual);
    if (expectedBytes.Length != actualBytes.Length ||
        !CryptographicOperations.FixedTimeEquals(expectedBytes, actualBytes))
    {
        throw new DomainException("internal_auth_failed", "내부 API 인증에 실패했습니다.");
    }
}

static void RequireEzbasePrivateAccess(HttpContext http, IConfiguration configuration)
{
    if (!PrivateNetworkPolicy.IsAllowed(http.Connection.RemoteIpAddress))
    {
        throw new DomainException(
            "private_network_required",
            "Ezbase 내부 연동 API는 사설망 또는 루프백 연결에서만 사용할 수 있습니다.");
    }

    RequireInternalKey(http, configuration);
}

public sealed record AuditEvent(
    DateTimeOffset OccurredAt,
    string EventType,
    string ActorId,
    string CompanyId,
    string DeviceId,
    string Result,
    string CorrelationId);

public sealed class AuditTrail
{
    private readonly object _gate = new();
    private readonly List<AuditEvent> _events = [];

    public void Add(
        string eventType,
        string actorId,
        string companyId,
        string deviceId,
        string result,
        string correlationId)
    {
        lock (_gate)
        {
            _events.Add(new AuditEvent(
                DateTimeOffset.UtcNow,
                eventType,
                actorId,
                companyId,
                deviceId,
                result,
                correlationId));
        }
    }

    public IReadOnlyList<AuditEvent> ReadAll()
    {
        lock (_gate)
        {
            return _events.ToArray();
        }
    }
}
