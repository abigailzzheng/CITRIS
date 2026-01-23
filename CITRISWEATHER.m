%% define locations (lat/lon)

locations = struct( ...
    "UC_Berkeley_Vertiport",  [37.8715, -122.2730], ... % center of UCB
    "UC_Davis_Vertiport",     [38.5449, -121.7405], ... % top of Hutchinson
    "UC_Merced_Vertiport",    [37.3646, -120.4277], ... % center of UCM
    "UC_SantaCruz_Vertiport", [36.9741, -122.0308], ... % center of UCSC
    "KNUQ", [37.4143, -122.0498], ... % Moffett Federal Airfield
    "KOAR", [36.6879, -121.8081], ... % Marina Municipal Airport
    "KSNS", [36.6770, -121.6554], ... % Salinas Municipal Airport
    "KCVH", [36.8930, -121.4100], ... % Hollister Municipal Airport
    "KSQL", [37.5071, -122.2492], ... % San Carlos Airport
    "KLVK", [37.6925, -121.8191] ...  % Livermore Municipal Airport
);

% location ICAO codes (for weather lookup)
airportCodes = {'KNUQ','KOAR','KSNS','KCVH','KSQL','KLVK'};

% URL: AviationWeather.gov's API data
awcBase = "https://aviationweather.gov/api/data";
icaoList = strjoin(airportCodes, ','); % serperate airport ICAO list into comma-separated string

%% METAR (current weather obs)
metarURL = sprintf('%s/metar?ids=%s&format=json&hours=3', awcBase, icaoList);
fprintf("Requesting METAR: %s\n", metarURL);
raw = webread(metarURL);  % JSON from the web API

if ischar(raw) || isstring(raw)
    metarJson = jsondecode(raw);
elseif iscell(raw)
    metarJson = raw{1};
else
    metarJson = raw;
end

%% parese METAR data

% store data in map (indexed by airport code)
metarData = containers.Map();

if isfield(metarJson, "features") && ~isempty(metarJson.features)
    feats = metarJson.features;
    if iscell(feats), feats = [feats{:}]; end
    for i = 1:numel(feats)
        props = feats(i).properties;
        metarData(props.station_id) = props;
    end
elseif isfield(metarJson, "data") && ~isempty(metarJson.data)
    for i = 1:numel(metarJson.data)
        record = metarJson.data(i);
        if isfield(record, "station_id")
            metarData(record.station_id) = record;
        end
    end
else
    fprintf("METAR response has no usable data.\n");
end

%% TAF (forecasts)
tafURL = sprintf('%s/taf?ids=%s&format=json', awcBase, icaoList);
fprintf("Requesting TAF: %s\n", tafURL);
raw = webread(tafURL);

if ischar(raw) || isstring(raw)
    tafJson = jsondecode(raw);
elseif iscell(raw)
    tafJson = raw{1};
else
    tafJson = raw;
end

%% parse TAF data
tafData = containers.Map();

if isfield(tafJson, "features") && ~isempty(tafJson.features)
    feats = tafJson.features;
    if iscell(feats), feats = [feats{:}]; end
    for i = 1:numel(feats)
        props = feats(i).properties;
        tafData(props.station_id) = props;
    end
elseif isfield(tafJson, "data") && ~isempty(tafJson.data)
    for i = 1:numel(tafJson.data)
        record = tafJson.data(i);
        if isfield(record, "station_id")
            tafData(record.station_id) = record;
        end
    end
else
    fprintf("TAF response has no usable data");
end

%% display weather reports

fprintf("METAR OBSERVATIONS\n");
for i = 1:numel(airportCodes)
    code = airportCodes{i};
    if isKey(metarData, code)
        p = metarData(code);
        try
            windStr = sprintf('%d° @ %d kt', p.wind_dir_degrees, p.wind_speed_kt);
            visStr  = sprintf('%g mi', p.visibility_statute_mi);
            tempStr = sprintf('%g°C', p.air_temperature_c);
            wxStr   = getfield(p, "wx_string");  % might be missing
        catch
            windStr = "N/A"; visStr = "N/A"; tempStr = "N/A"; wxStr = "N/A";
        end
        fprintf('%s: Wind=%s, Vis=%s, Temp=%s, Wx=%s\n', code, windStr, visStr, tempStr, wxStr);
    else
        fprintf('%s: NO METAR DATA\n', code);
    end
end

fprintf("\nTAF FORECASTS\n");
for i = 1:numel(airportCodes)
    code = airportCodes{i};
    if isKey(tafData, code)
        p = tafData(code);
        try
            rawTaf = strrep(p.raw_text, newline, ' / ');  % formatting
        catch
            rawTaf = "N/A";
        end
        fprintf('%s: %s\n', code, rawTaf);
    else
        fprintf('%s: NO TAF DATA\n', code);
    end
end

%% distance matrix b/w locations

names = fieldnames(locations);
n = numel(names);
distMatrix = zeros(n);

% loop over all pairs of locations + compute great-circle distance
for i = 1:n
    for j = 1:n
        if i == j
            distMatrix(i,j) = 0;  % distance to self is zero
        else
            coord1 = locations.(names{i});
            coord2 = locations.(names{j});
            distMatrix(i,j) = Circle(coord1, coord2);
        end
    end
end

% output table of distances
fprintf("\nDISTANCE MATRIX (NM)\n");
fprintf('%12s\t', 'From/To');
fprintf('%12s\t', names{:});
fprintf('\n');

for i = 1:n
    fprintf('%12s\t', names{i});
    fprintf('%12.1f\t', distMatrix(i,:));
    fprintf('\n');
end

fprintf("Weather + Distance analysis complete");

%% Haversine Great Circle distance
function nm = Circle(pt1, pt2)
    R = 6371.0;  % radius of earth in km
    dlat = deg2rad(pt2(1) - pt1(1));
    dlon = deg2rad(pt2(2) - pt1(2));
    a = sin(dlat/2)^2 + cos(deg2rad(pt1(1))) * cos(deg2rad(pt2(1))) * sin(dlon/2)^2;
    c = 2 * atan2(sqrt(a), sqrt(1-a));
    km = R * c;
    nm = km * 0.539957;  % convert km to nautical miles
end
