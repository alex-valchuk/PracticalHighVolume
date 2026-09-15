using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FlightCatalog.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "flight_catalog");

            migrationBuilder.CreateTable(
                name: "airports",
                schema: "flight_catalog",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    airport_code = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    city = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    timezone = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    latitude = table.Column<double>(type: "double precision", nullable: false),
                    longitude = table.Column<double>(type: "double precision", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_airports", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "flights",
                schema: "flight_catalog",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<int>(type: "integer", nullable: false),
                    aircraft_model = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    flight_no = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    arrival_airport = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    departure_airport = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    scheduled_arrival = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    scheduled_departure = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_flights", x => x.id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_airports_airport_code",
                schema: "flight_catalog",
                table: "airports",
                column: "airport_code",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_flights_status",
                schema: "flight_catalog",
                table: "flights",
                column: "status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "airports",
                schema: "flight_catalog");

            migrationBuilder.DropTable(
                name: "flights",
                schema: "flight_catalog");
        }
    }
}
