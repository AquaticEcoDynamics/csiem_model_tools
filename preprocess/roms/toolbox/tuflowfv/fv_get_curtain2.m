% /////// fv_get_curtain ///////
% function obj = fv_get_curtain(obj)
% Extracts TUFLOW-FV results (2D or 3D) at the cells which are intersected by obj.pline
%
% inputs
%   obj = handle to fvres_curtain object generated by fvres_curtain.m
%
% outputs
%   obj.results = structure with fields for each variables processed
%   obj.vert = verticees (patch object property) for curatin produced by fvg_curtain
%   obj.face = indexing of faces to vertices (patch object property) for curatin produced by fvg_curtain
%   obj.flux = flux across transect
%   obj.WORK = structure containing variables required during the processing, created on first call
%
% Jesper Nielsen, Copyright (C) BMTWBM 2014

function obj = fv_get_curtain2(obj)

% do the hard work once
if obj.WORK.refresh
    
    % clear away any old variables in structure
    obj.ResultsCurtain = struct();
    
    variables = cat(1,obj.Variables,{'layerface_Z'});
    nv = length(variables);
    
    % call fv_get_curtain_ids
    [ic2, coords, chain] = fv_get_curtain_ids(obj.Pline,obj.Geofil);
    nic2 = length(ic2);
    
    % was modelling performed in spherical coordinates
    tmp = ncreadatt(obj.Geofil,'/','spherical');
    switch tmp
        case 'true'
            spherical = true;
        case 'false'
            spherical = false;
    end
    
    % switch chainage to metres if required;
    if spherical
        if obj.Chainage
            [x,y,gz] = ll2utm(coords(:,1),coords(:,2));
            if sum(diff(gz,1,1)) ~= [0 0];
                error('cannot convert to cartesian coordinates as points extend beyond a single grid zone')
            end
            dx = cat(1,0,diff(x));
            dy = cat(1,0,diff(y));
            chain = cumsum(hypot(dx,dy));
        end
    end
    
    % info info info
    names = {'layerface_Z';'NL';'idx2';'idx3'};
    TMP = netcdf_get_var(obj.Nci,'names',names,'timestep',1);
    layerface_Z = TMP.layerface_Z;
    idx2 = TMP.idx2;
    idx3 = TMP.idx3;
    nl = TMP.NL;
    nlf = nl + 1;
    nc2 = length(idx3);
    nc3 = length(idx2);
    
    % ready yourself for netcdf.getVar
    [~,~,~,unlimdimid] = netcdf.inq(obj.Nci);
    is_3D = false(nv,1);
    is_zl = false(nv,1);
    for aa = 1:nv
        v_name = variables{aa};
        varid(aa) = netcdf.inqVarID(obj.Nci,v_name);
        [~, ~, dimids, ~] = netcdf.inqVar(obj.Nci,varid(aa));
        nd = length(dimids);
        START.(v_name) = zeros(nd,1);
        for bb = 1:nd
            [dimname,dimlen] = netcdf.inqDim(obj.Nci,dimids(bb));
            if dimids(bb) == unlimdimid;
                COUNT.(v_name)(bb) = 1;
                i_ud(aa) = bb;
            else
                COUNT.(v_name)(bb) = dimlen;
            end
            switch dimname
                case {'NumCells2D','NumSedFrac'}
                    error(['fv_get_curtain is applicable for 3D variables only, unlike ' v_name])
                case 'NumCells3D'
                    is_3D(aa) = true; % distinguish results from layerfaces
                case 'NumLayerFaces3D'
                    is_zl(aa) = true;    
            end
        end
    end
    
    % unit normal vectors
    norm = [-diff(coords(:,2)) diff(coords(:,1))];
    unorm_tmp(:,1) = norm(:,1) ./ hypot(norm(:,1),norm(:,2));
    unorm_tmp(:,2) = norm(:,2) ./ hypot(norm(:,1),norm(:,2));
    unorm = [];
    for aa = 1:nic2
        i = ic2(aa);
        unorm = cat(1,unorm,repmat(unorm_tmp(aa,:),nl(i),1));
    end
    
    % unit tangent vectors
    tang = [diff(coords(:,1)) diff(coords(:,2))];
    utang_tmp(:,1) = tang(:,1) ./ hypot(tang(:,1),tang(:,2));
    utang_tmp(:,2) = tang(:,2) ./ hypot(tang(:,1),tang(:,2));
    utang = [];
    for aa = 1:nic2
        i = ic2(aa);
        utang = cat(1,utang,repmat(utang_tmp(aa,:),nl(i),1));
    end
    
    % logical indexing into variables (faces values)
    ir = [];
    for aa = 1:nic2
        i = ic2(aa);
        k = idx3(i);
        kk = k + nl(i) - 1;
        ir = cat(1,ir,(k:kk)');
    end
    
    % indexing into layerfaces_Z (vert values)
    itop = double(idx3) + (0:nc2-1)';
    il = [];
    for aa = 1:nic2
        i = ic2(aa);
        tmp = itop(i):(itop(i) + nl(i));
        il = cat(1,il,tmp',tmp');
    end
    
    % patches
    % -- verticees
    nvert = length(il);
    vert = zeros(nvert,3);
    kk = 0;
    for aa = 1:nic2
        i = ic2(aa);
        % -- -- left side of rectangular patches
        j = kk + 1;
        jj = j + nlf(i) - 1;
        % -- -- right side of rectangular patches
        k = jj + 1;
        kk = k + nlf(i) - 1;
        if obj.Chainage
            vert(j:jj,1) = chain(aa);
            vert(k:kk,1) = chain(aa+1);
        else
            vert(j:jj,1:2) = repmat(coords(aa,:),nlf(i),1);
            vert(k:kk,1:2) = repmat(coords(aa+1,:),nlf(i),1);
        end
    end
    vert(:,3) = layerface_Z(il);
    
    % -- face to vert indexing
    nface = length(ir);
    face = zeros(nface,4);
    k = 1;
    for aa = 1:nic2
        i = ic2(aa);
        for bb = 1:nl(i)
            if bb == 1
                if aa == 1
                    face(k,1) = 1;
                else
                    face(k,1) = face(k-1,3) + 1;
                end
            else
                face(k,1) = face(k-1,4);
            end
            face(k,2) = face(k,1) + nlf(i);
            face(k,3) = face(k,2) + 1;
            face(k,4) = face(k,1) + 1;
            k = k+1;
        end
    end
    
    % preallocate and/or store
    obj.WORK.mod3 = zeros(nc3,1,nv,'single');
    obj.faces = face;
    
    % store small dicky variables
    v = {'coords','chain','unorm','utang','vert','face','variables','nv','varid','is_3D','i_ud','START','COUNT','vert','il','ir'};
    for aa = 1:length(v)
        eval(['obj.WORK.(v{aa}) = ' v{aa} ';'])
    end
    obj.WORK.refresh = false;
else
    v = {'coords','chain','unorm','utang','vert','face','variables','nv','varid','is_3D','i_ud','START','COUNT','vert','il','ir'};
    for aa = 1:length(v)
        eval([v{aa} ' = obj.WORK.(v{aa});'])
    end
end

% extract results
k = 1;
for aa = 1:nv
    v_name = variables{aa};
    START.(v_name)(i_ud(aa)) = obj.TimeStep - 1;
    if is_3D(aa)
        obj.WORK.mod3(:,1,k) = netcdf.getVar(obj.Nci,varid(aa),START.(v_name),COUNT.(v_name));
        k = k+1;
    else
        lay = netcdf.getVar(obj.Nci,varid(aa),START.(v_name),COUNT.(v_name));
    end
end

% index into curtain
k = 1;
for aa = 1:nv
    v_name = variables{aa};
    if is_3D(aa)
        obj.ResultsCurtain.(v_name) = obj.WORK.mod3(ir,:,k);
        k = k+1;
    else
        vert(:,3) = lay(il);
    end
end

% -- face areas
% dx = vert(face(:,2),1) - vert(face(:,1),1);
% dy = vert(face(:,2),2) - vert(face(:,1),2);
% dz = vert(face(:,2),3) - vert(face(:,3),3);
% obj.area = hypot(dx,dy) .* dz;  % this needs to be preallocated and perhaps these calculations should only be performed when flux output is desired

% -- face centres WHY WAS I DOING THIS
% C.face_centre(:,1) = (vert(face(:,2),1) + vert(face(:,1),1)) / 2;
% C.face_centre(:,2) = (vert(face(:,2),2) + vert(face(:,1),2)) / 2;
% C.face_centre(:,3) = (vert(face(:,2),3) + vert(face(:,3),3)) / 2;

obj.vertices = vert;