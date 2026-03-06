import { pool } from '../db/pool.js';

export async function createNotification({ userId, title, body, kind, db = pool }) {
  await db.query(
    `INSERT INTO notifications (user_id, title, body, kind) VALUES ($1,$2,$3,$4)`,
    [userId, title, body, kind],
  );
}

export async function queueNightReminderForAllUsers() {
  const users = await pool.query('SELECT id FROM users');
  for (const user of users.rows) {
    await createNotification({
      userId: user.id,
      title: 'Order Reminder',
      body: 'Place your order before 9 PM for next-morning delivery.',
      kind: 'NIGHT_REMINDER',
    });
  }
}
