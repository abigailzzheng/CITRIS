
clear; clc;

% eBird API KEY
EBIRD_API_KEY = 'YOUR_EBIRD_API_KEY_HERE'; % eBird API token

% Search radius (km)
searchRadiusKM = 40;

%% get location

prompt = {'Enter latitude:','Enter longitude:'};
dlgtitle = 'Current Flight Position';
dims = [1 35];
answer = inputdlg(prompt, dlgtitle, dims);
lat = str2double(answer{1});
lon = str2double(answer{2});

fprintf('\nFetching bird risk data for (%.4f, %.4f)…\n', lat, lon);

%% recent sightings

fprintf('Downloading recent eBird sightings…\n');


baseURL = 'https://api.ebird.org/v2/data/obs/geo/recent'; % API endpoint

headers = [
    "X-eBirdApiToken" EBIRD_API_KEY
];

params = {
    'lat', lat, ...
    'lng', lon, ...
    'dist', searchRadiusKM, ...
    'maxResults', 200
};

try
    data = webread(baseURL, params{:}, headers{:});
catch ME
    warning('eBird API request failed:\n%s', ME.message);
    data = [];
end
