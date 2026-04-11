import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DeploymentEnvService, DeploymentEnv } from '../services/deployment-env.service';
import { Observable } from 'rxjs';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './dashboard.component.html',
  styleUrls: ['./dashboard.component.css']
})
export class DashboardComponent implements OnInit {
  env$!: Observable<DeploymentEnv>;
  now = new Date();

  constructor(private envService: DeploymentEnvService) {}

  ngOnInit(): void {
    this.env$ = this.envService.env$;
    setInterval(() => (this.now = new Date()), 30_000);
  }

  refresh(): void {
    this.now = new Date();
    this.envService.refresh();
  }

  formatDate(iso: string): string {
    if (!iso || iso === 'N/A') return '—';
    try {
      return new Date(iso).toLocaleString();
    } catch {
      return iso;
    }
  }
}