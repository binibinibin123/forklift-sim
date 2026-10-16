// Godot(scripts/iap.gd)와 앱인토스 인앱결제 SDK 사이의 다리.
// Godot은 window.aitBridge.init(cb) / buy() / restore() 를 부르고,
// cb에는 JSON 문자열 이벤트를 넘긴다: owned / price / failed.
import { IAP } from '@apps-in-toss/web-framework';

// 토스 콘솔에 등록한 비소모성 상품의 SKU
export const SKU = 'forkliftsim_unlock';

let send = () => {};
let busy = false;

function emit(ev) {
  try { send(JSON.stringify(ev)); } catch (e) { console.error(e); }
}

async function findOwned() {
  // 결제는 됐지만 지급 처리가 안 된 주문을 먼저 마무리한다.
  try {
    const pending = (await IAP.getPendingOrders()) || [];
    const list = Array.isArray(pending) ? pending : pending.orders || [];
    for (const o of list) {
      if (o.sku === SKU) {
        await IAP.completeProductGrant({ params: { orderId: o.orderId } });
        return true;
      }
    }
  } catch (e) { console.warn('pending', e); }
  // 완료·환불 기록에서 가장 최근 상태를 본다(기기를 바꿔도 유지).
  let key, latest = null;
  for (let page = 0; page < 20; page++) {
    const r = await IAP.getCompletedOrRefundedOrders(key ? { key } : undefined);
    for (const o of r.orders || []) {
      if (o.sku === SKU && (!latest || o.date > latest.date)) latest = o;
    }
    if (!r.hasNext || !r.nextKey) break;
    key = r.nextKey;
  }
  return latest ? latest.status === 'COMPLETED' : false;
}

async function refresh() {
  try {
    emit({ type: 'owned', value: await findOwned() });
  } catch (e) {
    console.warn('restore', e); // 오프라인 등: 저장된 상태를 그대로 둔다
  }
}

async function loadPrice() {
  try {
    const { products } = await IAP.getProductItemList();
    const p = (products || []).find((x) => x.sku === SKU);
    if (p) emit({ type: 'price', value: p.displayAmount });
  } catch (e) { console.warn('price', e); }
}

window.aitBridge = {
  init(cb) {
    send = cb;
    loadPrice();
    refresh();
  },
  buy() {
    if (busy) return;
    busy = true;
    let cleanup;
    try {
      cleanup = IAP.createOneTimePurchaseOrder({
        options: {
          sku: SKU,
          processProductGrant: () => {
            emit({ type: 'owned', value: true });
            return true;
          },
        },
        onEvent: (event) => {
          if (event.type === 'success') emit({ type: 'owned', value: true });
          busy = false;
          cleanup?.();
        },
        onError: (error) => {
          busy = false;
          cleanup?.();
          if (error?.code === 'ITEM_ALREADY_OWNED') { refresh(); return; }
          if (error?.code !== 'USER_CANCELED') emit({ type: 'failed' });
        },
      });
    } catch (e) {
      busy = false;
      console.error(e);
      emit({ type: 'failed' });
    }
  },
  restore() {
    refresh();
  },
};
