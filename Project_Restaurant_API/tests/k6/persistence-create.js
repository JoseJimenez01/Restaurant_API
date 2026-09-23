import http from 'k6/http';
import { check, fail } from 'k6';

const API_URL = __ENV.API_URL || 'http://api:8080';
const KEYCLOAK_URL = __ENV.KEYCLOAK_URL || 'http://auth:8080';
const REALM = __ENV.KEYCLOAK_REALM || 'restaurant';
const CLIENT_ID = __ENV.KEYCLOAK_CLIENT_ID || 'restaurant-api';
const CLIENT_SECRET = __ENV.KEYCLOAK_CLIENT_SECRET || '';
const USERNAME = __ENV.K6_WRITER_USERNAME || 'k6_writer';
const PASSWORD = __ENV.K6_WRITER_PASSWORD || '';
const RESOURCE_PATH = __ENV.RESOURCE_PATH || '/reservas';
const MARKER = __ENV.PERSISTENCE_MARKER;
const DATE = __ENV.PERSISTENCE_DATE;

export const options = {
    vus: 1,
    iterations: 1,
    thresholds: {
        checks: ['rate==1'],
        http_req_failed: ['rate==0'],
    },
};

function token() {
    const data = {
        grant_type: 'password',
        client_id: CLIENT_ID,
        username: USERNAME,
        password: PASSWORD,
    };
    if (CLIENT_SECRET !== '') data.client_secret = CLIENT_SECRET;

    const r = http.post(
        `${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token`,
        data,
        { responseCallback: http.expectedStatuses(200), tags: { name: 'keycloak-token-writer' } }
    );

    if (!check(r, { 'Keycloak entrega token writer': (x) => x.status === 200 })) {
        fail(`No se pudo obtener token: ${r.status} ${r.body}`);
    }
    return r.json('access_token');
}

export default function () {
    if (!MARKER || !DATE || !PASSWORD) {
        fail('Faltan PERSISTENCE_MARKER, PERSISTENCE_DATE o K6_WRITER_PASSWORD.');
    }

    const accessToken = token();
    const body = JSON.stringify({
        nombre: MARKER,
        fecha: DATE,
        cantidadPersonas: 3,
    });

    const response = http.post(`${API_URL}${RESOURCE_PATH}`, body, {
        headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
        },
        responseCallback: http.expectedStatuses(201),
        tags: { name: 'persistencia-crear' },
    });

    check(response, {
        'Persistencia: POST responde 201': (r) => r.status === 201,
        'Persistencia: recurso contiene marcador': (r) => r.body.includes(MARKER),
    });
}
