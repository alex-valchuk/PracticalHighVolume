var builder = DistributedApplication.CreateBuilder(args);

builder.AddProject<Projects.FlightCatalog_Api>("api");

builder.Build().Run();
