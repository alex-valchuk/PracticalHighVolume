import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { TableModule, SortIcon } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { Airport } from '../../core/api/models/airport.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { AirportsService } from './airports.service';

@Component({
  selector: 'app-airports-page',
  standalone: true,
  imports: [FormsModule, DecimalPipe, TableModule, SortIcon, ButtonModule, InputTextModule, TagModule],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Airports</h1>
          <p class="subtitle">Reference data synchronized from the external source</p>
        </div>
        <div class="actions">
          <button pButton type="button" icon="pi pi-refresh"
                  label="Sync now"
                  [loading]="syncing()"
                  (click)="sync()"></button>
        </div>
      </div>

      <p-table
        [value]="airports()"
        [loading]="loading()"
        [paginator]="true"
        [rows]="20"
        [rowsPerPageOptions]="[10, 20, 50, 100]"
        [globalFilterFields]="['code', 'name', 'city', 'timezone']"
        #dt
        styleClass="p-datatable-sm">

        <ng-template #caption>
          <div class="table-caption">
            <input pInputText type="text"
                   placeholder="Search by code, name, city..."
                   (input)="dt.filterGlobal($any($event.target).value, 'contains')" />
            <span class="count">{{ airports().length }} airports</span>
          </div>
        </ng-template>

        <ng-template #header>
          <tr>
            <th pSortableColumn="code">Code <p-sort-icon field="code"></p-sort-icon></th>
            <th pSortableColumn="name">Name <p-sort-icon field="name"></p-sort-icon></th>
            <th pSortableColumn="city">City <p-sort-icon field="city"></p-sort-icon></th>
            <th>Timezone</th>
            <th>Coordinates</th>
          </tr>
        </ng-template>

        <ng-template #body let-airport>
          <tr>
            <td><p-tag [value]="airport.code" severity="info"></p-tag></td>
            <td>{{ airport.name }}</td>
            <td>{{ airport.city }}</td>
            <td>{{ airport.timezone }}</td>
            <td class="coords">
              {{ airport.latitude | number:'1.2-2' }},
              {{ airport.longitude | number:'1.2-2' }}
            </td>
          </tr>
        </ng-template>

        <ng-template #emptymessage>
          <tr>
            <td colspan="5" class="empty">
              No airports. Click "Sync now" to import from the external source.
            </td>
          </tr>
        </ng-template>
      </p-table>
    </div>
  `,
  styles: [`
    .table-caption { display: flex; align-items: center; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
    .count { color: var(--text-muted); font-size: 0.9rem; }
    .coords { color: var(--text-muted); font-family: monospace; font-size: 0.85rem; }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
  `]
})
export class AirportsPage implements OnInit {
  private readonly service = inject(AirportsService);
  private readonly messages = inject(MessageService);

  readonly airports = signal<Airport[]>([]);
  readonly loading = signal(false);
  readonly syncing = signal(false);

  ngOnInit(): void { this.load(); }

  private load(): void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (resp) => {
        this.airports.set(resp.items);
        this.loading.set(false);
      },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load airports', detail: err.message });
      }
    });
  }

  sync(): void {
    this.syncing.set(true);
    this.service.sync().subscribe({
      next: (r) => {
        this.syncing.set(false);
        this.messages.add({
          severity: 'success',
          summary: 'Sync completed',
          detail: `Read: ${r.read}, created: ${r.created}, updated: ${r.updated}, skipped: ${r.skipped}`
        });
        this.load();
      },
      error: (err: ApiError) => {
        this.syncing.set(false);
        this.messages.add({ severity: 'error', summary: 'Sync failed', detail: err.message });
      }
    });
  }
}