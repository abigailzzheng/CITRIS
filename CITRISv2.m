
locations = struct( ...
    "UC_Berkeley_Vertiport",  [37.8715, -122.2730], ...
    "UC_Davis_Vertiport",     [38.5449, -121.7405], ...
    "UC_Merced_Vertiport",    [37.3646, -120.4277], ...
    "UC_SantaCruz_Vertiport", [36.9741, -122.0308], ...
    "KNUQ", [37.4143, -122.0498], ...
    "KOAR", [36.6879, -121.8081], ...
    "KSNS", [36.6770, -121.6554], ...
    "KCVH", [36.8930, -121.4100], ...
    "KSQL", [37.5071, -122.2492], ...
    "KLVK", [37.6925, -121.8191], ...
    "KEDU", [38.5317, -121.7860], ... % Proxy for UC Davis
    "KOAK", [37.7213, -122.2207], ... % Proxy for UC Berkeley
    "KWVI", [36.9390, -121.7900], ... % Proxy for UC Santa Cruz
    "KMCE", [37.2847, -120.5146] ...  % Proxy for UC Merced
);

proxyMap = containers.Map( ...
    {'UC_Davis_Vertiport','UC_Berkeley_Vertiport','UC_SantaCruz_Vertiport','UC_Merced_Vertiport'}, ...
    {'KEDU','KOAK','KWVI','KMCE'} ...
);

icaoStations = {'KEDU','KOAK','KWVI','KMCE','KNUQ','KOAR','KSNS','KCVH','KSQL','KLVK'};

%% METAR and TAF

metarData = containers.Map();
tafData = containers.Map();

for i = 1:numel(icaoStations)
    icao = icaoStations{i};

    % METAR
    metarURL = sprintf('https://api.weather.gov/stations/%s/observations/latest', icao);
    try
        obs = webread(metarURL);
        metarData(icao) = obs;
    catch
        fprintf('METAR not available for %s\n', icao);
    end

    % TAF
    tafURL = sprintf('https://api.weather.gov/forecasts/taf/stations/%s', icao);
    try
        forecast = webread(tafURL);
        tafData(icao) = forecast;
    catch
        fprintf('TAF not available for %s\n', icao);
    end
end

%% display METAR

fprintf("\nMETAR OBSERVATIONS (via NWS)\n");

for i = 1:numel(icaoStations)
    icao = icaoStations{i};
    if isKey(metarData, icao)
        p = metarData(icao).properties;
        try
            tempC = p.temperature.value;
            windSpd = p.windSpeed.value;
            windDir = p.windDirection.value;
            visKM = p.visibility.value;
            wx = p.textDescription;

            fprintf('%s: Temp=%.1f°C, Wind=%d° @ %.0f kt, Vis=%.1f km, Wx=%s\n', ...
                icao, tempC, windDir, windSpd, visKM, wx);
        catch
            fprintf('%s: METAR data missing fields\n', icao);
        end
    else
        fprintf('%s: NO METAR DATA\n', icao);
    end
end

%% display TAF

fprintf("\nTAF FORECASTS (via NWS)\n");

for i = 1:numel(icaoStations)
    icao = icaoStations{i};
    if isKey(tafData, icao)
        try
            tafRaw = tafData(icao).properties.rawMessage;
            fprintf('%s: %s\n', icao, tafRaw);
        catch
            fprintf('%s: TAF missing raw text\n', icao);
        end
    else
        fprintf('%s: NO TAF DATA\n', icao);
    end
end

fprintf("\nCAMPUS VERTIPORT WEATHER (via nearest ICAO proxy)\n");
campuses = keys(proxyMap);

for i = 1:numel(campuses)
    campus = campuses{i};
    icao = proxyMap(campus);

    if isKey(metarData, icao)
        p = metarData(icao).properties;
        try
            tempC = p.temperature.value;
            windSpd = p.windSpeed.value;
            windDir = p.windDirection.value;
            visKM = p.visibility.value;
            wx = p.textDescription;

            fprintf('%s (via %s): Temp=%.1f°C, Wind=%d° @ %.0f kt, Vis=%.1f km, Wx=%s\n', ...
                campus, icao, tempC, windDir, windSpd, visKM, wx);
        catch
            fprintf('%s (via %s): METAR fields missing\n', campus, icao);
        end
    else
        fprintf('%s (via %s): NO METAR DATA\n', campus, icao);
    end
end

%% distance matrix

fprintf("\nDISTANCE MATRIX (NM)\n");

names = fieldnames(locations);
n = numel(names);
distMatrix = zeros(n);

for i = 1:n
    for j = 1:n
        if i == j
            distMatrix(i,j) = 0;
        else
            coord1 = locations.(names{i});
            coord2 = locations.(names{j});
            distMatrix(i,j) = haversineNM(coord1, coord2);
        end
    end
end

% header 
fprintf('%12s\t', 'From/To');
fprintf('%12s\t', names{:});
fprintf('\n');

% rows
for i = 1:n
    fprintf('%12s\t', names{i});
    fprintf('%12.1f\t', distMatrix(i,:));
    fprintf('\n');
end

fprintf("\nWeather + Distance analysis complete.\n");

%% great circle distance 
function nm = haversineNM(pt1, pt2)
    R = 6371.0;
    dlat = deg2rad(pt2(1) - pt1(1));
    dlon = deg2rad(pt2(2) - pt1(2));
    a = sin(dlat/2)^2 + cos(deg2rad(pt1(1))) * cos(deg2rad(pt2(1))) * sin(dlon/2)^2;
    c = 2 * atan2(sqrt(a), sqrt(1-a));
    km = R * c;
    nm = km * 0.539957;
end
