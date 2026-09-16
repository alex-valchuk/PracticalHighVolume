import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ToastModule } from 'primeng/toast';
import { ConfirmDialog } from 'primeng/confirmdialog';
import { SidebarComponent } from './core/layout/sidebar.component';
import { HeaderComponent } from './core/layout/header.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, SidebarComponent, HeaderComponent, ToastModule, ConfirmDialog],
  template: `
    <div class="app-shell">
      <app-sidebar></app-sidebar>
      <div class="app-main">
        <app-header></app-header>
        <main class="app-content">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
    <p-toast position="top-right"></p-toast>
    <p-confirmdialog></p-confirmdialog>
  `,
  styles: [`
    .app-shell { display: flex; min-height: 100vh; }
    .app-main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
    .app-content { flex: 1; padding: 1.5rem 2rem; overflow-y: auto; }
  `]
})
export class AppComponent {}