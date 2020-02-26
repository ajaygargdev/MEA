using System;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.OpenApi.Models;
using Serilog;
using Swashbuckle.AspNetCore.SwaggerUI;

namespace Kmd.Momentum.Mea.Api
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

#pragma warning disable CA1822
        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            services.AddMvc()
                .AddJsonOptions(a =>
                {
                    a.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
                    a.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
                });

            services.AddControllers();

            services.AddMea();
            services.AddHealthChecks().AddCheck("basic_readiness_check", () => new HealthCheckResult(status: HealthStatus.Healthy), new[] { "ready" });
            services.Configure<HealthCheckPublisherOptions>(options =>
            {
                options.Predicate = (check) => check.Tags.Contains("ready");
            });

            services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo
                {
                    Version = "v1",
                    Title = "KMD Logic STS Bridge",
                    Description = "A simple example ASP.NET Core Web API",
                    TermsOfService = new Uri("https://example.com/terms"),
                });

                var securityScheme = new OpenApiSecurityScheme
                {
                    In = ParameterLocation.Header,
                    Description = "Please enter 'Bearer' followed by space and a JWT from logic",
                    Name = "Authorization",
                    Type = SecuritySchemeType.ApiKey,
                    Scheme = "bearer",
                    Reference = new OpenApiReference
                    {
                        Type = ReferenceType.SecurityScheme,
                        Id = "Bearer"
                    }
                };
                c.AddSecurityDefinition("Bearer", securityScheme);
                var securityRequirement = new OpenApiSecurityRequirement();
                securityRequirement.Add(securityScheme, new[] { "Bearer" });
                c.AddSecurityRequirement(securityRequirement);
            });
        }

        public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            app.UseSerilogRequestLogging();
            app.UseRouting();
            app.UseAuthentication();
            app.UseAuthorization();
            app.UseStaticFiles(); // Use with c.InjectStylesheet("/swagger-ui/custom.css");
            app.UseSwagger();
            app.UseSwaggerUI(c =>
            {
                c.SwaggerEndpoint("/swagger/v1/swagger.json", "Momentum External Api");
                //    c.SwaggerEndpoint($"/swagger/case/swagger.json", $"KMD Case Service API");
                //    c.InjectStylesheet("https://fonts.googleapis.com/css?family=Roboto");
                //    c.InjectStylesheet("/swagger-ui/custom.css");
                c.DefaultModelRendering(ModelRendering.Model);
                c.DisplayRequestDuration();
                c.RoutePrefix = string.Empty;
            });

            app.UseHttpsRedirection();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapControllers();
            });
        }
    }
#pragma warning restore CA1822
}