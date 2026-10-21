using EzbaseViewer.Contracts;
using EzbaseViewer.Core;

var tests = new (string Name, Action Run)[]
{
    ("실행 코드는 한 번만 소비된다", LaunchCodeCanOnlyBeConsumedOnce),
    ("만료된 실행 코드는 거부된다", ExpiredLaunchCodeIsRejected),
    ("다른 업체 클라이언트 접근은 거부된다", CrossCompanyAccessIsRejected),
    ("클라이언트는 Host 전용으로 등록된다", ClientIsEnrolledAsHostOnly),
    ("철회된 무인 접속은 거부된다", UnattendedAccessPolicyIsEnforced),
    ("허용 기능을 확장한 요청은 거부된다", CapabilityEscalationIsRejected)
};

var failures = new List<string>();
foreach (var test in tests)
{
    try
    {
        test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception exception)
    {
        failures.Add($"FAIL {test.Name}: {exception.Message}");
    }
}

foreach (var failure in failures)
{
    Console.Error.WriteLine(failure);
}

return failures.Count == 0 ? 0 : 1;

static void LaunchCodeCanOnlyBeConsumedOnce()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var service = new LaunchCodeService(clock);
    var issued = service.Issue(CreateLaunchRequest("device-a"), TimeSpan.FromSeconds(60));
    _ = service.Consume(issued.Code);
    AssertDomainCode("launch_code_invalid_or_reused", () => service.Consume(issued.Code));
}

static void ExpiredLaunchCodeIsRejected()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var service = new LaunchCodeService(clock);
    var issued = service.Issue(CreateLaunchRequest("device-a"), TimeSpan.FromSeconds(60));
    clock.Advance(TimeSpan.FromSeconds(61));
    AssertDomainCode("launch_code_expired", () => service.Consume(issued.Code));
}

static void CrossCompanyAccessIsRejected()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var companies = new CompanyDirectory(clock);
    companies.Create(new CompanyCreateRequest("company-b", "B 업체"));
    var devices = new DeviceDirectory(clock, companies);
    devices.Enroll(new DeviceEnrollmentRequest("device-b", "company-b", "B PC", "public-key", true));
    var sessions = new SessionService(clock, devices);
    var caller = new AppTokenContext(
        "user-a",
        "org-a",
        "company-a",
        "device-b",
        new HashSet<RemoteCapability> { RemoteCapability.ViewScreen },
        clock.GetUtcNow().AddMinutes(5));

    AssertDomainCode(
        "cross_company_access_denied",
        () => sessions.Create(caller, new SessionCreateRequest(
            "device-b",
            false,
            new[] { RemoteCapability.ViewScreen })));
}

static void ClientIsEnrolledAsHostOnly()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var companies = new CompanyDirectory(clock);
    companies.Create(new CompanyCreateRequest("company-a", "A 업체"));
    var devices = new DeviceDirectory(clock, companies);
    var client = devices.Enroll(new DeviceEnrollmentRequest("device-a", "company-a", "A PC", "public-key", true));

    if (client.InstallationMode != ClientInstallationMode.HostOnly)
    {
        throw new InvalidOperationException("클라이언트가 Host 전용 모드로 등록되지 않았습니다.");
    }
}

static void UnattendedAccessPolicyIsEnforced()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var companies = new CompanyDirectory(clock);
    companies.Create(new CompanyCreateRequest("company-a", "A 업체"));
    var devices = new DeviceDirectory(clock, companies);
    devices.Enroll(new DeviceEnrollmentRequest("device-a", "company-a", "A PC", "public-key", false));
    var sessions = new SessionService(clock, devices);
    var caller = CreateCaller(clock, "device-a");

    AssertDomainCode(
        "unattended_access_denied",
        () => sessions.Create(caller, new SessionCreateRequest(
            "device-a",
            true,
            new[] { RemoteCapability.ViewScreen })));
}

static void CapabilityEscalationIsRejected()
{
    var clock = new ManualTimeProvider(DateTimeOffset.Parse("2026-10-21T00:00:00Z"));
    var companies = new CompanyDirectory(clock);
    companies.Create(new CompanyCreateRequest("company-a", "A 업체"));
    var devices = new DeviceDirectory(clock, companies);
    devices.Enroll(new DeviceEnrollmentRequest("device-a", "company-a", "A PC", "public-key", true));
    var sessions = new SessionService(clock, devices);
    var caller = CreateCaller(clock, "device-a");

    AssertDomainCode(
        "capability_denied",
        () => sessions.Create(caller, new SessionCreateRequest(
            "device-a",
            false,
            new[] { RemoteCapability.ViewScreen, RemoteCapability.TransferFiles })));
}

static LaunchCodeIssueRequest CreateLaunchRequest(string deviceId) => new(
    "user-a",
    "org-a",
    "company-a",
    deviceId,
    new[] { RemoteCapability.ViewScreen },
    Guid.NewGuid().ToString("N"));

static AppTokenContext CreateCaller(ManualTimeProvider clock, string deviceId) => new(
    "user-a",
    "org-a",
    "company-a",
    deviceId,
    new HashSet<RemoteCapability> { RemoteCapability.ViewScreen },
    clock.GetUtcNow().AddMinutes(5));

static void AssertDomainCode(string expected, Action action)
{
    try
    {
        action();
    }
    catch (DomainException exception) when (exception.Code == expected)
    {
        return;
    }

    throw new InvalidOperationException($"예상 오류 코드 {expected}가 발생하지 않았습니다.");
}

internal sealed class ManualTimeProvider(DateTimeOffset now) : TimeProvider
{
    private DateTimeOffset _now = now;

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan duration) => _now = _now.Add(duration);
}
