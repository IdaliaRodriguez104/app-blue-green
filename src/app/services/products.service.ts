import { Injectable } from '@angular/core';
import { ref, onValue } from 'firebase/database';
import { db } from "../firebase.config";
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class ProductsService {

  private productsSubject = new BehaviorSubject<any[]>([]);
  products$ = this.productsSubject.asObservable();

  constructor() {
    this.loadProducts();
  }

  loadProducts() {
    const productsRef = ref(db, 'products');

    onValue(productsRef, (snapshot) => {
      const data = snapshot.val();
      if (data) {
        this.productsSubject.next(data);
      }
    });
  }
}