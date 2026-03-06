function RouteFind3dV2()
    % WRAPPER FUNCTION: Ensures sub-functions work on all MATLAB versions
    clc; close all;

    % --- 1. CONFIGURATION ---
    % Region: Davis --> Berkeley
    latlim = [37.800 38.600];
    lonlim = [-122.350 -121.650];
    altLim = [0 5000]; % Altitude in feet

    % Start (Davis) & End (Berkeley) @ 100ft AGL
    startPt = [38.532, -121.785, 100];
    destPt  = [37.871, -122.273, 100];

    % Obstacles: [Lat, Lon, Radius_KM, Ceiling_FT]
    obstacles = [
        38.550, -121.750, 1.2, 2000;  % Davis Tower
        38.260, -121.930, 20.0, 4000; % Travis AFB (The big red zone)
        38.000, -122.100, 3.0, 1500;  % Hills
        38.100, -122.200, 8.0, 2500   % Metro
    ];

    bufferKm = 0.5; % Safety margin (1.5 km away from obstacles)
    altRes  = 25;   % Vertical layers (Higher = smoother climbing)

    % --- 2. GENERATE ASPECT-CORRECT GRID ---
    fprintf('Initializing Map...\n');
    degToKmLat = 111.0;
    degToKmLon = 111.0 * cosd(mean(latlim));

    latDist = (latlim(2) - latlim(1)) * degToKmLat;
    lonDist = (lonlim(2) - lonlim(1)) * degToKmLon;

    % Aspect Ratio Correction: Calculate Grid Width to match aspect ratio
    gridH = 200;
    gridW = round(gridH * (lonDist / latDist));

    map.minLat = min(latlim); map.maxLat = max(latlim);
    map.minLon = min(lonlim); map.maxLon = max(lonlim);
    map.minAlt = altLim(1);   map.maxAlt = altLim(2);

    % Helpers to convert between World(Lat/Lon) and Grid(Indices)
    toGrid = @(lat, lon, alt) [ ...
        min(gridH, max(1, round(((lat-map.minLat)/(map.maxLat-map.minLat))*(gridH-1))+1)), ...
        min(gridW, max(1, round(((lon-map.minLon)/(map.maxLon-map.minLon))*(gridW-1))+1)), ...
        min(altRes, max(1, round(((alt-map.minAlt)/(map.maxAlt-map.minAlt))*(altRes-1))+1)) ];

    % --- 3. BUILD OBSTACLES (FAST METHOD) ---
    fprintf('Building Obstacles...\n');
    gridMap     = false(gridH, gridW, altRes);
    planningMap = false(gridH, gridW, altRes); % The "Ghost" map for safety

    [X,Y] = meshgrid(1:gridW, 1:gridH);

    for i = 1:size(obstacles,1)
        latO   = obstacles(i,1);
        lonO   = obstacles(i,2);
        radKm  = obstacles(i,3);
        ceilFt = obstacles(i,4);

        % 1. Visual Map (Actual size)
        radPx = (radKm / degToKmLat / (map.maxLat-map.minLat)) * gridH;
        ceilLayer = round(((ceilFt - map.minAlt) / (map.maxAlt - map.minAlt)) * (altRes-1)) + 1;
        ceilLayer = min(max(ceilLayer,1), altRes);

        center = toGrid(lat0, lon0, 0); 
        mask2D = ((X-center(2)).^2 + (Y-center(1)).^2) <= radPx^2;

        gridMap(:,:,1:ceilLayer) = bsxfun(@or, gridMap(:,:,1:ceilLayer), mask2D);

        totalRadKm = radKm + bufferKm;
        radPxSafe = (totalRadKm / degToKmLat / (map.maxLat-map.minLat)) * gridH;
        mask2DSafe = ((X-center(2)).^2 + (Y-center(1)).^2) <= radPxSafe^2;

        zmaxS = min(altRes, ceilLayer+1);
        planningMap(:,:,1:zmaxS) = bsxfun(@or, planningMap(:,:,1:zmaxS), mask2DSafe);
    end

    % --- 4. PATHFINDING (A*) ---
    fprintf('Running 3D A* Search...\n');
    sIdx = toGrid(startPt(1), startPt(2), startPt(3));
    gIdx = toGrid(destPt(1),  destPt(2),  destPt(3));

    if planningMap(sIdx(1),sIdx(2),sIdx(3)) || planningMap(gIdx(1),gIdx(2),gIdx(3))
        warning('Start/End is inside safety buffer! Attempting to proceed anyway...');
    end

    pathIdx = runAStar3D_fast(planningMap, sIdx, gIdx);

    if isempty(pathIdx)
        warning('NO PATH FOUND');
        return;
    end

    % --- 5. GRID -> WORLD (vectorized) ---
    r = pathIdx(:,1); c = pathIdx(:,2); z = pathIdx(:,3);

    lat = ((r-1)/(gridH-1))*(map.maxLat-map.minLat) + map.minLat;
    lon = ((c-1)/(gridW-1))*(map.maxLon-map.minLon) + map.minLon;
    alt = ((z-1)/(altRes-1))*(map.maxAlt-map.minAlt) + map.minAlt;

    rawPath = [lat, lon, alt];

    % --- 6. SMOOTHING (same as your original) ---
    waypoints = rawPath;
    if size(waypoints,1) > 2
        % 1. Iron out the A* grid "staircase" effect
        % A window size of ~10 averages out the jagged 45/90 degree grid steps
        windowSize = 10;
        smoothedWp = smoothdata(waypoints, 'gaussian', windowSize);

        % 2. Calculate cumulative physical distance 
        stepDists = sqrt(sum(diff(smoothedWp).^2, 2));
        t = [0; cumsum(stepDists)];

        % 3. Dynamic point count to guarantee high-res curves
        numPoints = max(500, size(smoothedWp,1) * 4);
        t_smooth = linspace(0, t(end), numPoints);

        % 4. Interpolate the newly ironed-out points
        sLat = interp1(t, smoothedWp(:,1), t_smooth, 'makima')';
        sLon = interp1(t, smoothedWp(:,2), t_smooth, 'makima')';
        sAlt = interp1(t, smoothedWp(:,3), t_smooth, 'makima')';
    else
        sLat = waypoints(:,1); sLon = waypoints(:,2); sAlt = waypoints(:,3);
    end

    % --- 6. VISUALIZATION ---
    fprintf('Plotting...\n');

    % Convert all units to Kilometers relative to Start Point for clean 3D plotting
    ftToKm = 0.0003048;
    toRelKm = @(lat_, lon_, alt_) [(lon_-startPt(2))*degToKmLon, (lat_-startPt(1))*degToKmLat, alt_*ftToKm];

    figure('Color','w', 'Name', 'Optimal Flight Path', 'Renderer','painters'); hold on; grid on;

    % Data Prep
    pathKm  = toRelKm(sLat, sLon, sAlt);
    startKm = toRelKm(startPt(1), startPt(2), startPt(3));
    endKm   = toRelKm(destPt(1),  destPt(2),  destPt(3));

    % Draw Obstacles
    for i = 1:size(obstacles,1)
        latO   = obstacles(i,1);
        lonO   = obstacles(i,2);
        radKm  = obstacles(i,3);
        ceilFt = obstacles(i,4);

        cKm = toRelKm(latO, lonO, 0);
        ceilKm = ceilFt * ftToKm;

        [xc, yc, zc] = cylinder(radKm, 30);
        xc = xc + cKm(1); yc = yc + cKm(2); zc = zc * ceilKm;

        % Draw visual obstacle (Red)
        surf(xc, yc, zc, 'FaceColor','r', 'FaceAlpha', 0.4, 'EdgeColor','none');
        patch(xc(1,:), yc(1,:), zc(2,:), 'r', 'FaceAlpha', 0.4);

        % Optional: Draw wireframe of Safety Buffer (Dotted Gray)
        [xcS, ycS, zcS] = cylinder(radKm + bufferKm, 30);
        xcS = xcS + cKm(1); ycS = ycS + cKm(2); zcS = zcS * ceilKm;
        plot3(xcS(1,:), ycS(1,:), zeros(1,31), 'k:', 'Color', [0.6 0.6 0.6]);
    end

    % Draw Path & Shadow
    plot3(pathKm(:,1), pathKm(:,2), zeros(size(pathKm,1),1), 'Color', [0.8 0.8 0.8], 'LineWidth', 2); % Shadow
    plot3(pathKm(:,1), pathKm(:,2), pathKm(:,3), 'b-', 'LineWidth', 3); % Main path

    % Draw Waypoints
    plot3(startKm(1), startKm(2), startKm(3), 'gp', 'MarkerFaceColor','g', 'MarkerSize', 12);
    plot3(endKm(1),   endKm(2),   endKm(3),   'rp', 'MarkerFaceColor','r', 'MarkerSize', 12);

    % Drop lines for waypoints
    for i = 1:50:size(pathKm,1) % Draw a line every 50 points
        plot3([pathKm(i,1) pathKm(i,1)], [pathKm(i,2) pathKm(i,2)], [0 pathKm(i,3)], 'k:', 'LineWidth', 0.5);
    end

    % Setup View
    xlabel('East (km)'); ylabel('North (km)'); zlabel('Altitude (km)');
    title('3D Flight Route [Vertical Exaggeration: 15x]');
    view(-30, 30);
    daspect([1 1 1/5]); % Vertical Exaggeration: makes mountains look 15x taller

end

% --- LOCAL FUNCTIONS ---
% ======================================================================
% FAST 3D A*: heap PQ + precomputed neighbors + linear increments
% ======================================================================
function path = runAStar3D_fast(map, start, goal)

    [rows, cols, lays] = size(map);
    N = numel(map);
    plane = rows*cols;

    % linear index: lin = r + (c-1)*rows + (l-1)*rows*cols
    startLin = uint32(start(1) + (start(2)-1)*rows + (start(3)-1)*plane);
    goalLin  = uint32(goal(1)  + (goal(2)-1)*rows + (goal(3)-1)*plane);

    gScore = inf(N,1,'single');
    gScore(startLin) = 0;

    parent = zeros(N,1,'uint32');
    closed = false(N,1);

    % 26 neighbors
    [DR,DC,DL] = ndgrid(-1:1,-1:1,-1:1);
    nbr = [DR(:),DC(:),DL(:)];
    nbr(all(nbr==0,2),:) = [];
    nbr = int16(nbr); % 26x3

    % step cost identical to your original
    baseCost = single(sqrt(sum(single(nbr).^2,2)));
    stepCost = baseCost;
    stepCost(nbr(:,3)~=0) = stepCost(nbr(:,3)~=0) * 2.5;

    % linear increments
    dLin = int32(nbr(:,1)) + int32(nbr(:,2))*int32(rows) + int32(nbr(:,3))*int32(plane);

    % Priority queue keyed on f = g + h
    pq = pqCreate(N);

    % heuristic at start (explicit sqrt, no norm())
    dr0 = single(start(1) - goal(1));
    dc0 = single(start(2) - goal(2));
    dl0 = single(start(3) - goal(3));
    h0  = sqrt(dr0*dr0 + dc0*dc0 + dl0*dl0);

    pq = pqPush(pq, startLin, h0);

    found = false;

    while pq.size > 0
        [pq, currLin, ~] = pqPopMin(pq);

        if closed(currLin)
            continue;
        end
        closed(currLin) = true;

        if currLin == goalLin
            found = true;
            break;
        end

        % lin -> (r,c,l) once per expansion
        idx0 = double(currLin) - 1;
        cl = floor(idx0/plane) + 1;
        rem = idx0 - (cl-1)*plane;
        cc = floor(rem/rows) + 1;
        cr = rem - (cc-1)*rows + 1;

        for k = 1:26
            nr = cr + nbr(k,1);
            nc = cc + nbr(k,2);
            nl = cl + nbr(k,3);

            if nr<1||nr>rows || nc<1||nc>cols || nl<1||nl>lays
                continue;
            end

            nLin = uint32(int32(currLin) + dLin(k));

            if map(nLin) || closed(nLin)
                continue;
            end

            tentative_g = gScore(currLin) + stepCost(k);

            if tentative_g < gScore(nLin)
                parent(nLin) = currLin;
                gScore(nLin) = tentative_g;

                % heuristic: explicit sqrt on singles (fixes your norm error)
                dr = single(nr - goal(1));
                dc = single(nc - goal(2));
                dl = single(nl - goal(3));
                h  = sqrt(dr*dr + dc*dc + dl*dl);

                f = tentative_g + h;

                if ~pqContains(pq, nLin)
                    pq = pqPush(pq, nLin, f);
                else
                    pq = pqDecreaseKey(pq, nLin, f);
                end
            end
        end
    end

    if ~found
        path = [];
        return;
    end

    % reconstruct path (chunked, O(L))
    tmp = zeros(4096,1,'uint32');
    k = 0;
    curr = goalLin;

    while curr ~= 0
        k = k + 1;
        if k > numel(tmp)
            tmp = [tmp; zeros(4096,1,'uint32')]; %#ok<AGROW>
        end
        tmp(k) = curr;
        if curr == startLin
            break;
        end
        curr = parent(curr);
    end

    tmp = tmp(k:-1:1);

    % vectorized lin -> (r,c,l)
    idx0 = double(tmp) - 1;
    l = floor(idx0/plane) + 1;
    rem = idx0 - (l-1)*plane;
    c = floor(rem/rows) + 1;
    r = rem - (c-1)*rows + 1;

    path = [r(:), c(:), l(:)];
end

% ======================================================================
% Priority queue (min-heap) with simple API
% ======================================================================
function pq = pqCreate(maxN)
    pq.node = zeros(maxN,1,'uint32');
    pq.key  = inf(maxN,1,'single');
    pq.pos  = zeros(maxN,1,'uint32');
    pq.size = uint32(0);
end

function tf = pqContains(pq, node)
    tf = pq.pos(node) ~= 0;
end

function pq = pqPush(pq, node, key)
    pq.size = pq.size + 1;
    i = pq.size;

    pq.node(i) = uint32(node);
    pq.key(i)  = single(key);
    pq.pos(node) = i;

    pq = pqSiftUp(pq, i);
end

function [pq, node, key] = pqPopMin(pq)
    node = pq.node(1);
    key  = pq.key(1);

    pq.pos(node) = 0;

    if pq.size == 1
        pq.size = uint32(0);
        return;
    end

    last = pq.node(pq.size);
    pq.node(1) = last;
    pq.key(1)  = pq.key(pq.size);
    pq.pos(last) = 1;

    pq.size = pq.size - 1;
    pq = pqSiftDown(pq, 1);
end

function pq = pqDecreaseKey(pq, node, newKey)
    i = pq.pos(node);
    if i == 0
        return;
    end
    newKey = single(newKey);
    if newKey >= pq.key(i)
        return;
    end
    pq.key(i) = newKey;
    pq = pqSiftUp(pq, i);
end

function pq = pqSiftUp(pq, i)
    while i > 1
        p = floor(double(i)/2);
        if pq.key(p) <= pq.key(i)
            break;
        end
        pq = pqSwap(pq, i, p);
        i = uint32(p);
    end
end

function pq = pqSiftDown(pq, i)
    while true
        l = 2*double(i);
        if l > double(pq.size)
            break;
        end
        r = l + 1;

        m = l;
        if r <= double(pq.size) && pq.key(r) < pq.key(l)
            m = r;
        end

        if pq.key(i) <= pq.key(m)
            break;
        end

        pq = pqSwap(pq, i, m);
        i = uint32(m);
    end
end

function pq = pqSwap(pq, i, j)
    ni = pq.node(i); nj = pq.node(j);
    ki = pq.key(i);  kj = pq.key(j);

    pq.node(i) = nj; pq.node(j) = ni;
    pq.key(i)  = kj; pq.key(j)  = ki;

    pq.pos(ni) = uint32(j);
    pq.pos(nj) = uint32(i);
end
