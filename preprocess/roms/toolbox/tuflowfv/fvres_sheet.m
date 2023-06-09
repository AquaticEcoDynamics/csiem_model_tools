% FVRES_SHEET     TUFLOW-FV sheet (2D) results object
%
%   resObj = fvres_sheet(resfil) creates a sheet (2D) results object.
%   resfil is the cell-centre netcdf results file generated by TUFLOW-FV.
%
%   resObj = fvres_sheet(resfil,'PropertyName',PropertyValue,...) creates
%   a sheet results object defined by the specified property name / property value
%   pairs. Default values are assigned to all unspecified properties.
%
%   Execute get(resObj), to see a list of the resObj's properties and
%   their current values.
%
%   Execute set(resObj,'PropertyName',PropertyValue) to change a
%   property of an existing resObj.
%
%
%   /-/-/-/-/-/-/-/-/ EXAMPLES /-/-/-/-/-/-/-/-/
%
%   (1): Create a resObj which contains processed (depth averaged) salinity and temperature results
%   resObj = fvres_sheet('mymodel.nc','variables',{'SAL';'TEMP'})
%
%   (2): Depth averaged the 3D results over the bottom 2 metres
%   set(resObj,'ref','height','range',[0 2])
%
%
%   /-/-/-/-/-/-/-/-/ PROPERTIES /-/-/-/-/-/-/-/-/
%
%   Type           ==> fvres_sheet
%
%   Resfil         ==> TUFLOW-FV cell-centre netcdf results file
%
%   Geofil         ==> TUFLOW-FV netcdf geometry file
%
%   TimeVector     ==> vector of output times within Resfil
%
%   TimeCurrent    ==> output time corresponding to results in resObj
%
%   TimeStep       ==> integer timestep corresponding to results in resObj
%
%   Variables      ==> variable to process, 2D variables recieve no processing
%
%   Expression     ==> string expression for customizing results
%
%   OutputType     {cell} | node ==> when node cellcenter results are interpolated to the nodes
% 
%   ResultsCell    ==> structure containing cellcenter results
%
%   ResultsNode    ==> structure containing cellcenter results interpolated onto the nodes
%
%   Ref            {sigma} | depth | height | elevation | top | bottom ==> how 3D results are depth averaged
%
%   Range          {[0 1]} | vector of length 2 ==> limits corresponding to Ref to depth average results over
%
%   BedRef         {[]} | integer ==> sediment fraction to visualise within bed variables, [] indicates the sum of all fractions
%
%   BedFrac        {false} | true ==> visualise whole value for fraction specified in BedRef or fraction of total
%
%   StampVec       ==> vector of logicals defining which cells to return results for
%
%   StampType      {hard} | soft ==> if hard then cells included in StampVec return a value regardless of wet/dry status
%
%
% See also FVRES_CURTAIN
%
% http://tuflow.com/fvforum/index.php?/forum/16-matlab/
% http://fvwiki.tuflow.com/index.php?title=Depth_Averaging_Results
% http://fvwiki.tuflow.com/index.php?title=MATLAB_TUTORIAL
%
% Jesper Nielsen, Copyright (C) BMTWBM 2014

classdef (CaseInsensitiveProperties = true) fvres_sheet < fvres
    properties (Constant)
        Type = 'fvres_sheet'
    end
    properties
        OutputType = 'cell' % {cell} | node
        ResultsCell = struct();
        ResultsNode = struct();
        Ref = 'sigma'   % {sigma} | elevation | height | depth | top | bot
        Range = [0 1]
        BedRef = []     % {[]}, sediment fractions within bed are summed
        BedFrac = false % true | {false}, are the processed results for the individual sediments within the bed a fraction of all the sediments
        StampVec
        StampType = 'hard'; %  {hard} | soft
    end
    properties (Hidden = true)
        ref_wait
    end
    methods
        % // constructor method //
        function obj = fvres_sheet(resfil,varargin)
            % Pre-initialization — Compute arguments for superclass constructor
            
            % Object initialization — Call superclass constructor
            obj@fvres(resfil);
            
            % Post initialization — Perform any operations related to the subclass, including referencing and assigning to the object, call class methods, passing the object to functions, and so on
            
            % -- optional inputs
            noi = length(varargin);
            if mod(noi,2) ~= 0
                error('expecting optional inputs as property / value pairs')
            end
            for aa = 1:2:noi
                set(obj,varargin{aa},varargin{aa+1});
            end
        end
        % // set methods //
        function set.Ref(obj,val)
            if fv_check_dave(val,obj.Range)
                obj.Ref = val;
                obj.ref_wait = [];
                workhorse(obj);
            else
                obj.ref_wait = val; % wait for potential set(obj,range) command
                display('waiting for a suitable range input')
            end
        end
        function set.Range(obj,val)
            if fv_check_dave(obj.Ref,val)
                obj.Range = val;
                workhorse(obj);
            elseif ~isempty(obj.ref_wait) % if ref & range are incompatible an error will be thrown here
                fv_check_dave(obj.ref_wait,val)
                obj.Range = val;
                set(obj,'ref',obj.ref_wait)
                display('found a suitable range input')
            else
                fv_check_dave(obj.Ref,val) % throw the error
            end
        end
        function set.BedRef(obj,val)
            fv_check_bedref(obj.Resfil,val)
            obj.Bedref = val;
            obj.WORK.refresh = true;
            obj.WORK_C2N.refresh = true;
            workhorse(obj)
        end
        function set.BedFrac(obj,val)
            if ~islogical(val)
                error('expecting input of type logical for bedfrac')
            end
            obj.BedFrac = val;
            obj.WORK.refresh = true;
            obj.WORK_C2N.refresh = true;
            workhorse(obj)
        end
        function set.OutputType(obj,val)
            if ~ismember(val,{'node';'cell'})
                error('expecting node or cell for property output_type')
            end
            obj.OutputType = val;
            workhorse(obj);
        end
        function set.StampVec(obj,val)
            if ~islogical(val)
                error('expecting vector of logicals for stamp_vec')
            end
            if length(val) ~= max(obj.WORK.idx2)
                error('expecting vector of length NumCells2D for stamp_vec')
            end
            obj.StampVec = val;
            obj.WORK.refresh = true;
            obj.WORK_C2N.refresh = true;
            workhorse(obj)
        end
        function set.StampType(obj,val)
            
            if ~ismember(lower(val),{'hard';'soft'})
                error('expecting hard or soft for stamp_type')
            end
            tmp = obj.StampVec;
            if isempty(tmp)
                display('set StampVec property before StampType')
            else
                obj.StampType = lower(val);
                set(obj,'StampVec',tmp)
            end
        end
        % // get methods //
        % // retrieve and process results //
        function workhorse(obj)
            obj = fv_get_sheet(obj);
            switch obj.OutputType
                case 'node'
                    obj = fv_cell2node(obj);
            end
            obj.notify('update_patches')
        end
    end
end
% // sub functions //
