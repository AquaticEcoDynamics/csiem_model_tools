% /////// fv_cell2node ///////
% obj = fv_cell2node(obj)
%
% Interpolates the cell-centre results generated by fv_get_sheet.m onto the cell vertices (nodes).
% The interpolation uses cell to node weightings provided in the TUFLOW-FV _geo.nc file.
% The cell to node weightings are updated when cells have a NaN value.
% fv_get_sheet assigns NaNs to cells which are dry, stamped out and/or beyond the
% specified depth averaging limits.
% When it is not possible for the 3D results to be beyond the depth
% averaging limits ie. when obj.ref = 'sigma' then the calculations
% can be sped up.
%
% inputs
%   obj = fvres_sheet object
%
% outputs
%   obj = same as input but with a new / updated field called results_node.
%       This is a structure containing the cell centre model results interpolated onto the nodes.
%
% Jesper Nielsen, Copyright (C) BMTWBM 2014

function obj = fv_cell2node(obj)

% are all results within depth averaging limits. When results or
% the variables being visualised are 2D then it is unlikely that
% obj.ref has been set to anything and it should be at its default value
if strcmpi(obj.Ref,'sigma')
    express = true;
else
    express = false;
end

if isfield(obj.WORK_C2N,'ref') && ~strcmpi(obj.Ref,obj.WORK_C2N.ref) % has obj.ref been updated
    obj.WORK_C2N.refresh = true;
end

if obj.WORK_C2N.refresh
    
    % clear away any old variables in structure
    obj.ResultsNode = struct();
    
    % variables
    variables = fieldnames(obj.ResultsCell);
    variables = setxor(variables,'stat');
    nv = length(variables);
    
    % info from _geo.nc file
    GEO = netcdf_get_var(obj.Geofil,'names',{'node_NVC2';'node_cell2d_idx';'node_cell2d_weights'});
    nvc = GEO.node_NVC2;                              % number of cells for which given node is a vertice
    idx = GEO.node_cell2d_idx;                        % cell id's corresponning to nodes
    wts = GEO.node_cell2d_weights;                    % cell weights corresponning to nodes
    nn = length(nvc);
    nc_max = max(nvc);
    ne = nn * nc_max;
    
    if express
        % reformatting matrix used to put all cells connected to nodes on unique rows - makes summing a sinch
        i = false(nc_max,nn);
        for aa = 1:nn
            i(1:nvc(aa),aa) = true;
        end
        ind = [];
        
        % weightings when all cells are wet
        wts_mat  = zeros(nc_max,nn);
        wts_mat(i) = wts;
        
        % preallocate memory
        tmp = zeros(nc_max,nn,'single');
        res2D_nod_mat = zeros(nc_max,nn,nv,'single');
        stat_mat = false(nc_max,nn);
        wts_new = zeros(nc_max,nn);
    else
        % reformatting matrix used to put all cells connected to nodes on unique rows - makes summing a sinch
        i = false(nc_max,nn,nv);
        for aa = 1:nn
            i(1:nvc(aa),aa,:) = true;
        end
        ind = find(i(:,:,1));
        
        % weightings when all cells are wet
        wts_mat  = zeros(nc_max,nn,nv);
        wts_mat(i) = repmat(wts,[1 1 nv]);
        
        % preallocate memory
        tmp = [];
        res2D_nod_mat = zeros(nc_max,nn,nv,'single');
        stat_mat = false(nc_max,nn,nv);
        wts_new = zeros(nc_max,nn,nv);
    end
    
    % store away for next call
    obj.WORK_C2N.variables = variables;
    obj.WORK_C2N.nv = nv;
    obj.WORK_C2N.idx = idx;
    obj.WORK_C2N.i = i;
    obj.WORK_C2N.ind = ind;
    obj.WORK_C2N.ne = ne;
    obj.WORK_C2N.tmp = tmp;
    obj.WORK_C2N.res2D_nod_mat = res2D_nod_mat;
    obj.WORK_C2N.stat_mat = stat_mat;
    obj.WORK_C2N.wts_mat = wts_mat;
    obj.WORK_C2N.wts_new = wts_new;
    obj.WORK_C2N.refresh = false;
    obj.WORK_C2N.ref = obj.Ref;
else
    variables = obj.WORK_C2N.variables;
    nv = obj.WORK_C2N.nv;
    idx = obj.WORK_C2N.idx;
    ne = obj.WORK_C2N.ne;
    i = obj.WORK_C2N.i;
    ind = obj.WORK_C2N.ind;
    tmp = obj.WORK_C2N.tmp;
    res2D_nod_mat = obj.WORK_C2N.res2D_nod_mat;
    stat_mat = obj.WORK_C2N.stat_mat;
    wts_mat = obj.WORK_C2N.wts_mat;
    wts_new = obj.WORK_C2N.wts_new;
end

if express
    % wet cells
    stat_mat(i) = obj.ResultsCell.stat(idx);
    
    % multiple variables are processsed simultaneously so pack them together
    for aa = 1:nv
        v_name = variables{aa};       
        tmp(i) = obj.ResultsCell.(v_name)(idx);
        tmp(~stat_mat) = 0; % eliminate NaN's (assigned to dry cells by fv_get-sheet) as they are included in the summing (step after next)
        res2D_nod_mat(:,:,aa) = tmp;
    end
    
    % update weightings to account for dry cells.
    % -- when one or more of the cells connected to a node goes dry their respective weightings are reassigned to the remaining wet cells
    wts_new(stat_mat) = wts_mat(stat_mat);
    tot = sum(wts_new,1);
    wts_new = bsxfun(@rdivide,wts_new,tot);  % NaNs are generated by 0/0 ie all the cells connected to the node are dry
    
    % factor results
    res2D_nod_mat = bsxfun(@times,res2D_nod_mat,wts_new);
else
    
    % multiple variables are processsed simultaneously so pack them together
    % dry cells or cells beyond the depth averaging limits in fv_get_sheet have been assigned NaN
    for aa = 1:nv
        v_name = variables{aa};
        k = ne * (aa-1);
        res2D_nod_mat(ind + k) = obj.ResultsCell.(v_name)(idx);  % could be upgraded to have logical indexing
        stat_mat(ind + k) = ~isnan(res2D_nod_mat(ind + k));
    end
    
    % update weightings to account for dry cells.
    % -- when one or more of the cells connected to a node goes dry and/or falls outside the depth avering limits then their respective weightings are reassigned to the remaining cells
    wts_new(stat_mat) = wts_mat(stat_mat);
    tot = sum(wts_new,1);
    wts_new = bsxfun(@rdivide,wts_new,tot);
    
    % eliminate NaN's as they are included in the summing (next step)
    res2D_nod_mat(isnan(res2D_nod_mat)) = 0;
    
    % factor results
    res2D_nod_mat = res2D_nod_mat .* wts_new;
    
end
res2D_nod = sum(res2D_nod_mat,1);

% reasigning to structure
for aa = 1:nv
    v_name = variables{aa};
    obj.ResultsNode.(v_name) = res2D_nod(1,:,aa)';
end