import { Injectable } from '@angular/core';
import { ref, onValue } from 'firebase/database';
import { db } from '../firebase.config';
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class MenuService {

  private menuSubject = new BehaviorSubject<any[]>([]);
  menu$ = this.menuSubject.asObservable();

  constructor() {
    this.loadMenu();
  }

    loadMenu() {
    const menuRef = ref(db, 'menu');

    onValue(menuRef, (snapshot) => {
        const data = snapshot.val();

        if (data) {
        const arrayData = Object.values(data); // 🔥 CLAVE
        this.menuSubject.next(arrayData);
        }
    });
    }
}