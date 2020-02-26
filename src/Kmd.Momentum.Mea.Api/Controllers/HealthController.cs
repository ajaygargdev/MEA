using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using System.Net;
using System.Threading.Tasks;

namespace Kmd.Momentum.Mea.Api.Controllers
{
    [Route("[controller]/[action]")]
    //[Authorize]
    public class HealthController : Controller
    {
        private readonly HealthCheckService _healthCheckService;

        public HealthController(HealthCheckService healthCheckService)
        {
            _healthCheckService = healthCheckService;
        }

        /// <summary>
        ///     Get Health
        /// </summary>
        /// <remarks>Provides an indication about the health of the API</remarks>
        /// <response code="200">API is healthy</response>
        /// <response code="503">API is unhealthy or in degraded state</response>
        [HttpGet]
        [ProducesResponseType(typeof(HealthReport), (int)HttpStatusCode.OK)]
        // [Authorize(Scopes.Access)]
        public async Task<IActionResult> Ready()
        {
            var report = await _healthCheckService.CheckHealthAsync().ConfigureAwait(true);

            return report.Status == HealthStatus.Healthy ? Ok(report) : StatusCode((int)HttpStatusCode.ServiceUnavailable, report);
        }

        /// <summary>
        ///     Get Health
        /// </summary>
        /// <remarks>Provides an indication about the health of the API</remarks>
        /// <response code="200">API is healthy</response>
        /// <response code="503">API is unhealthy or in degraded state</response>
        [HttpGet]
        [ProducesResponseType(typeof(HealthReport), (int)HttpStatusCode.OK)]
        // [Authorize(Scopes.Access)]
        public async Task<IActionResult> Live()
        {
            var report = await _healthCheckService.CheckHealthAsync().ConfigureAwait(true);

            return report.Status == HealthStatus.Healthy ? Ok(report) : StatusCode((int)HttpStatusCode.ServiceUnavailable, report);
        }
    }
}