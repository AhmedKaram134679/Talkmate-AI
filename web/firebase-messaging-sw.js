/*
 * Service Worker for Web Push Notifications
 * This file must be placed in /web directory
 */

self.addEventListener('push', function(event) {
  if (event.data) {
    try {
      const payload = event.data.json();
      
      // [STABILIZATION]: Check both top-level and data-block for maximum compatibility
      const title = payload.title || (payload.data && payload.data.title) || 'رسالة جديدة';
      const body = payload.body || (payload.data && payload.data.body) || 'لديك رسالة جديدة في TalkMate AI';
      
      const options = {
        body: body,
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data || {},
        tag: 'chat-notification',
        renotify: true
      };

      event.waitUntil(
        self.registration.showNotification(title, options)
      );
    } catch (e) {
      console.error('Error parsing push payload:', e);
      // Fallback for non-JSON payloads
      event.waitUntil(
        self.registration.showNotification('TalkMate AI', {
          body: event.data.text(),
          icon: '/icons/Icon-192.png'
        })
      );
    }
  }
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  
  const data = event.notification.data;
  const chatId = data.chat_id;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      // If a window is already open, focus it
      for (let i = 0; i < clientList.length; i++) {
        let client = clientList[i];
        if (client.url.includes('/') && 'focus' in client) {
          if (chatId) {
            client.navigate('/#/chat/' + chatId);
          }
          return client.focus();
        }
      }
      // If no window is open, open a new one
      if (clients.openWindow) {
        let url = '/';
        if (chatId) url = '/#/chat/' + chatId;
        return clients.openWindow(url);
      }
    })
  );
});
