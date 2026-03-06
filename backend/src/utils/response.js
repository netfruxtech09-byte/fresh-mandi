export const ok = (res, data, message = 'OK') => res.json({ message, data });
export const fail = (res, status, message) => res.status(status).json({ message });
