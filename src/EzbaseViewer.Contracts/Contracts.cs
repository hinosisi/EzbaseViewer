namespace EzbaseViewer.Contracts;

public enum ClientInstallationMode
{
    HostOnly
}

public enum RemoteCapability
{
    ViewScreen,
    ControlKeyboard,
    ControlMouse,
    SelectMonitor,
    TransferFiles,
    RebootAndReconnect
}

public enum SessionState
{
    PendingApproval,
    Authorized,
    Denied,
    Terminated
}

public sealed record LaunchCodeIssueRequest(
    string UserId,
    string OrganizationId,
    string CompanyId,
    string DeviceId,
    IReadOnlyCollection<RemoteCapability> RequestedCapabilities,
    string Nonce);

public sealed record LaunchCodeIssueResponse(string Code, DateTimeOffset ExpiresAt);

public sealed record LaunchCodeExchangeRequest(string Code, string AppInstanceId, string AppVersion);

public sealed record LaunchCodeExchangeResponse(
    string AppToken,
    DateTimeOffset ExpiresAt,
    string DeviceId,
    string DeviceDisplayName,
    IReadOnlyCollection<RemoteCapability> AllowedCapabilities);

public sealed record CompanyCreateRequest(string CompanyId, string DisplayName);

public sealed record CompanyResponse(
    string CompanyId,
    string DisplayName,
    DateTimeOffset CreatedAt,
    int ClientCount);

public sealed record DeviceEnrollmentRequest(
    string DeviceId,
    string CompanyId,
    string DisplayName,
    string PublicKey,
    bool AllowUnattendedAccess);

public sealed record DeviceEnrollmentResponse(
    string DeviceId,
    string CompanyId,
    ClientInstallationMode InstallationMode,
    DateTimeOffset EnrolledAt);

public sealed record ManagedClientResponse(
    string DeviceId,
    string CompanyId,
    string DisplayName,
    ClientInstallationMode InstallationMode,
    bool AllowUnattendedAccess,
    DateTimeOffset EnrolledAt);

public sealed record SessionCreateRequest(
    string DeviceId,
    bool Unattended,
    IReadOnlyCollection<RemoteCapability> RequestedCapabilities);

public sealed record SessionCreateResponse(
    string SessionId,
    SessionState State,
    IReadOnlyCollection<RemoteCapability> GrantedCapabilities,
    DateTimeOffset ExpiresAt);

public sealed record SessionDecisionRequest(bool Approved, string Reason);

public sealed record SessionDecisionResponse(string SessionId, SessionState State, DateTimeOffset ChangedAt);

public sealed record ApiError(string Code, string Message, string CorrelationId);

public sealed record RemoteEngineProfileResponse(
    string EngineName,
    string ClientVersion,
    string ClientCommit,
    string ServerName,
    string ServerVersion,
    string ServerCommit,
    string License,
    string DecisionStatus);
