using System.Collections.Concurrent;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using EzbaseViewer.Contracts;

namespace EzbaseViewer.Core;

public sealed record LaunchContext(
    string UserId,
    string OrganizationId,
    string CompanyId,
    string DeviceId,
    IReadOnlySet<RemoteCapability> RequestedCapabilities,
    string Nonce,
    DateTimeOffset ExpiresAt);

public sealed record AppTokenContext(
    string UserId,
    string OrganizationId,
    string CompanyId,
    string DeviceId,
    IReadOnlySet<RemoteCapability> AllowedCapabilities,
    DateTimeOffset ExpiresAt);

public sealed record DeviceRecord(
    string DeviceId,
    string CompanyId,
    string DisplayName,
    string PublicKey,
    ClientInstallationMode InstallationMode,
    bool AllowUnattendedAccess,
    DateTimeOffset EnrolledAt);

public sealed record CompanyRecord(string CompanyId, string DisplayName, DateTimeOffset CreatedAt);

public sealed record SessionRecord(
    string SessionId,
    string UserId,
    string CompanyId,
    string DeviceId,
    bool Unattended,
    IReadOnlySet<RemoteCapability> GrantedCapabilities,
    SessionState State,
    DateTimeOffset ExpiresAt);

public sealed class DomainException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public static class RemoteEngineSelection
{
    public static RemoteEngineProfileResponse Current { get; } = new(
        "RustDesk",
        "1.4.9",
        "6c57829",
        "RustDesk Server OSS",
        "1.1.16",
        "73523b3",
        "AGPL-3.0",
        "Confirmed");
}

public static class PrivateNetworkPolicy
{
    public static bool IsAllowed(IPAddress? address)
    {
        if (address is null)
        {
            return false;
        }

        if (IPAddress.IsLoopback(address))
        {
            return true;
        }

        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        var bytes = address.GetAddressBytes();
        if (bytes.Length == 4)
        {
            return bytes[0] == 10 ||
                   bytes[0] == 127 ||
                   bytes[0] == 192 && bytes[1] == 168 ||
                   bytes[0] == 172 && bytes[1] is >= 16 and <= 31 ||
                   bytes[0] == 169 && bytes[1] == 254;
        }

        return bytes.Length == 16 &&
               ((bytes[0] & 0xFE) == 0xFC || bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80);
    }
}

public sealed class LaunchCodeService(TimeProvider timeProvider)
{
    private static readonly TimeSpan MaximumLifetime = TimeSpan.FromMinutes(5);
    private readonly ConcurrentDictionary<string, LaunchContext> _codes = new(StringComparer.Ordinal);

    public LaunchCodeIssueResponse Issue(LaunchCodeIssueRequest request, TimeSpan lifetime)
    {
        ValidateRequired(request.UserId, nameof(request.UserId));
        ValidateRequired(request.OrganizationId, nameof(request.OrganizationId));
        ValidateRequired(request.CompanyId, nameof(request.CompanyId));
        ValidateRequired(request.DeviceId, nameof(request.DeviceId));
        ValidateRequired(request.Nonce, nameof(request.Nonce));

        if (lifetime <= TimeSpan.Zero || lifetime > MaximumLifetime)
        {
            throw new DomainException("invalid_lifetime", "실행 코드 유효기간이 허용 범위를 벗어났습니다.");
        }

        if (request.RequestedCapabilities.Count == 0)
        {
            throw new DomainException("capabilities_required", "요청 기능이 하나 이상 필요합니다.");
        }

        var code = TokenUtility.CreateOpaqueToken();
        var expiresAt = timeProvider.GetUtcNow().Add(lifetime);
        var context = new LaunchContext(
            request.UserId,
            request.OrganizationId,
            request.CompanyId,
            request.DeviceId,
            request.RequestedCapabilities.ToHashSet(),
            request.Nonce,
            expiresAt);

        if (!_codes.TryAdd(TokenUtility.Hash(code), context))
        {
            throw new InvalidOperationException("실행 코드 충돌이 발생했습니다.");
        }

        return new LaunchCodeIssueResponse(code, expiresAt);
    }

    public LaunchContext Consume(string code)
    {
        ValidateRequired(code, nameof(code));

        if (!_codes.TryRemove(TokenUtility.Hash(code), out var context))
        {
            throw new DomainException("launch_code_invalid_or_reused", "실행 코드가 유효하지 않거나 이미 사용되었습니다.");
        }

        if (context.ExpiresAt <= timeProvider.GetUtcNow())
        {
            throw new DomainException("launch_code_expired", "실행 코드가 만료되었습니다.");
        }

        return context;
    }

    private static void ValidateRequired(string value, string field)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new DomainException("required_field", $"{field} 값이 필요합니다.");
        }
    }
}

public sealed class AppTokenService(TimeProvider timeProvider)
{
    private static readonly TimeSpan TokenLifetime = TimeSpan.FromMinutes(5);
    private readonly ConcurrentDictionary<string, AppTokenContext> _tokens = new(StringComparer.Ordinal);

    public (string Token, AppTokenContext Context) Issue(LaunchContext launch)
    {
        var token = TokenUtility.CreateOpaqueToken();
        var context = new AppTokenContext(
            launch.UserId,
            launch.OrganizationId,
            launch.CompanyId,
            launch.DeviceId,
            launch.RequestedCapabilities,
            timeProvider.GetUtcNow().Add(TokenLifetime));

        _tokens[TokenUtility.Hash(token)] = context;
        return (token, context);
    }

    public AppTokenContext Validate(string token)
    {
        if (string.IsNullOrWhiteSpace(token) ||
            !_tokens.TryGetValue(TokenUtility.Hash(token), out var context))
        {
            throw new DomainException("app_token_invalid", "앱 토큰이 유효하지 않습니다.");
        }

        if (context.ExpiresAt <= timeProvider.GetUtcNow())
        {
            _tokens.TryRemove(TokenUtility.Hash(token), out _);
            throw new DomainException("app_token_expired", "앱 토큰이 만료되었습니다.");
        }

        return context;
    }
}

public sealed class CompanyDirectory(TimeProvider timeProvider)
{
    private readonly ConcurrentDictionary<string, CompanyRecord> _companies = new(StringComparer.Ordinal);

    public CompanyRecord Create(CompanyCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.CompanyId) || string.IsNullOrWhiteSpace(request.DisplayName))
        {
            throw new DomainException("invalid_company", "업체 ID와 표시 이름이 필요합니다.");
        }

        var company = new CompanyRecord(request.CompanyId, request.DisplayName, timeProvider.GetUtcNow());
        if (!_companies.TryAdd(company.CompanyId, company))
        {
            throw new DomainException("company_already_exists", "이미 등록된 업체입니다.");
        }

        return company;
    }

    public CompanyRecord Get(string companyId) =>
        _companies.TryGetValue(companyId, out var company)
            ? company
            : throw new DomainException("company_not_found", "업체를 찾을 수 없습니다.");

    public IReadOnlyList<CompanyRecord> List() =>
        _companies.Values.OrderBy(company => company.DisplayName, StringComparer.Ordinal).ToArray();
}

public sealed class DeviceDirectory(TimeProvider timeProvider, CompanyDirectory companies)
{
    private readonly ConcurrentDictionary<string, DeviceRecord> _devices = new(StringComparer.Ordinal);

    public DeviceRecord Enroll(DeviceEnrollmentRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId) ||
            string.IsNullOrWhiteSpace(request.CompanyId) ||
            string.IsNullOrWhiteSpace(request.DisplayName) ||
            string.IsNullOrWhiteSpace(request.PublicKey))
        {
            throw new DomainException("invalid_device", "장치 등록 필수 값이 누락되었습니다.");
        }

        _ = companies.Get(request.CompanyId);

        var record = new DeviceRecord(
            request.DeviceId,
            request.CompanyId,
            request.DisplayName,
            request.PublicKey,
            ClientInstallationMode.HostOnly,
            request.AllowUnattendedAccess,
            timeProvider.GetUtcNow());

        if (!_devices.TryAdd(record.DeviceId, record))
        {
            throw new DomainException("device_already_enrolled", "이미 등록된 장치입니다.");
        }

        return record;
    }

    public DeviceRecord Get(string deviceId) =>
        _devices.TryGetValue(deviceId, out var device)
            ? device
            : throw new DomainException("device_not_found", "장치를 찾을 수 없습니다.");

    public IReadOnlyList<DeviceRecord> ListByCompany(string companyId)
    {
        _ = companies.Get(companyId);
        return _devices.Values
            .Where(device => string.Equals(device.CompanyId, companyId, StringComparison.Ordinal))
            .OrderBy(device => device.DisplayName, StringComparer.Ordinal)
            .ToArray();
    }
}

public sealed class SessionService(TimeProvider timeProvider, DeviceDirectory devices)
{
    private static readonly TimeSpan SessionAuthorizationLifetime = TimeSpan.FromMinutes(2);
    private readonly ConcurrentDictionary<string, SessionRecord> _sessions = new(StringComparer.Ordinal);

    public SessionRecord Create(AppTokenContext caller, SessionCreateRequest request)
    {
        var device = devices.Get(request.DeviceId);

        if (!string.Equals(caller.DeviceId, request.DeviceId, StringComparison.Ordinal) ||
            !string.Equals(caller.CompanyId, device.CompanyId, StringComparison.Ordinal))
        {
            throw new DomainException("cross_company_access_denied", "대상 업체의 클라이언트에 접근할 권한이 없습니다.");
        }

        var requested = request.RequestedCapabilities.ToHashSet();
        if (requested.Count == 0 || !requested.IsSubsetOf(caller.AllowedCapabilities))
        {
            throw new DomainException("capability_denied", "허용되지 않은 원격 기능이 포함되어 있습니다.");
        }

        if (request.Unattended && !device.AllowUnattendedAccess)
        {
            throw new DomainException("unattended_access_denied", "대상 장치가 무인 접속을 허용하지 않습니다.");
        }

        var state = request.Unattended ? SessionState.Authorized : SessionState.PendingApproval;
        var session = new SessionRecord(
            Guid.NewGuid().ToString("N"),
            caller.UserId,
            caller.CompanyId,
            device.DeviceId,
            request.Unattended,
            requested,
            state,
            timeProvider.GetUtcNow().Add(SessionAuthorizationLifetime));

        _sessions[session.SessionId] = session;
        return session;
    }

    public SessionRecord Decide(string sessionId, bool approved)
    {
        while (_sessions.TryGetValue(sessionId, out var current))
        {
            if (current.State != SessionState.PendingApproval)
            {
                throw new DomainException("session_not_pending", "승인 대기 중인 세션이 아닙니다.");
            }

            if (current.ExpiresAt <= timeProvider.GetUtcNow())
            {
                throw new DomainException("session_authorization_expired", "세션 승인 시간이 만료되었습니다.");
            }

            var changed = current with { State = approved ? SessionState.Authorized : SessionState.Denied };
            if (_sessions.TryUpdate(sessionId, changed, current))
            {
                return changed;
            }
        }

        throw new DomainException("session_not_found", "세션을 찾을 수 없습니다.");
    }
}

internal static class TokenUtility
{
    public static string CreateOpaqueToken()
    {
        Span<byte> bytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public static string Hash(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes);
    }
}
