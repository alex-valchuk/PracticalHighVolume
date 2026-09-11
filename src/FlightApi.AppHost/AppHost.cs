var builder = DistributedApplication.CreateBuilder(args);

builder.AddProject<Projects.FlightApi>("api");

builder.Build().Run();
