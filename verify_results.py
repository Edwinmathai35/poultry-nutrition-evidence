"""Independent Python verification of R outputs. Run after Poultry_Analysis.R.
Requires numpy, pandas, scipy, openpyxl. Does not overwrite R estimates.
"""
from pathlib import Path
import hashlib,json
import numpy as np
import pandas as pd
from PIL import Image
from scipy.stats import t
ROOT=Path(__file__).resolve().parent
T=ROOT/'outputs/tables'
checks=[]
def check(name,condition,detail):
 checks.append(dict(check=name,passed=bool(condition),detail=str(detail)))
 if not condition:raise AssertionError(name+': '+str(detail))
manifest=pd.read_csv(ROOT/'governance/source_manifest.csv')
check('Pinned source SHA256',all(hashlib.sha256((ROOT/'data/raw'/r.file).read_bytes()).hexdigest()==r.sha256 for r in manifest.itertuples()),len(manifest))
m=pd.read_csv(ROOT/'data/processed/monthly_ratio.csv',parse_dates=['date'])
check('Complete monthly calendar',len(m)==200 and m.date.equals(pd.Series(pd.date_range('2010-01-01','2026-08-01',freq='MS'),name='date')),len(m))
pens=pd.read_csv(ROOT/'data/processed/trial_pens.csv')
check('Unique randomized pens',pens.PEN.nunique()==63 and pens.groupby('TREATMENT').size().eq(9).all(),len(pens))
# Independent matrix algebra, without R/sandwich or statsmodels.
effects=pd.read_csv(T/'causal_treatment_effects.csv')
levels=['CT','MedCP-HighSBM','MedCP-MedSBM','MedCP-NoSBM','LowCP-HighSBM','LowCP-MedSBM','LowCP-NoSBM']
maxdiff=0.
for endpoint in ['FCRD11D35','ADGD11D35']:
 for adjusted in [False,True]:
  X=np.column_stack([np.ones(len(pens))]+[(pens.TREATMENT==v).astype(float).to_numpy() for v in levels[1:]]+([pens.BWD10.to_numpy()-pens.BWD10.mean()] if adjusted else []))
  y=pens[endpoint].to_numpy();bread=np.linalg.inv(X.T@X);b=np.linalg.lstsq(X,y,rcond=None)[0]
  resid=y-X@b;h=np.einsum('ij,jk,ik->i',X,bread,X);df=len(y)-X.shape[1]
  for robust in [True,False]:
   v=bread@(X.T@(((resid/(1-h))**2)[:,None]*X))@bread if robust else bread*(resid@resid/df)
   se=np.sqrt(np.diag(v));a=effects[(effects.endpoint==endpoint)&(effects.specification==('baseline_adjusted' if adjusted else 'unadjusted'))&(effects.SE_type==('HC3' if robust else 'conventional'))].set_index('treatment').loc[levels[1:]]
   expected=np.column_stack([b[1:7],se[1:7],b[1:7]-t.ppf(.975,df)*se[1:7],b[1:7]+t.ppf(.975,df)*se[1:7],2*t.sf(abs(b[1:7]/se[1:7]),df)])
   diff=float(np.max(np.abs(a[['estimate','SE','lower95','upper95','p']].to_numpy()-expected)));maxdiff=max(maxdiff,diff)
check('Independent treatment estimates, SE, CI and p values',maxdiff<1e-9,maxdiff)
f=pd.read_csv(T/'rolling_forecasts.csv',parse_dates=['origin','target'])
check('Every forecast origin precedes target',bool((f.origin<f.target).all()),len(f))
naive=f[f.model=='Naive'];lookup=m.set_index('date').ratio
check('Naive predictions equal last observed value',np.max(abs(naive.pred.to_numpy()-lookup.loc[naive.origin].to_numpy()))<1e-12,len(naive))
a=pd.read_csv(T/'forecast_accuracy.csv')
metric_error=0.
for (split,h,model),d in f.groupby(['split','h','model']):
 r=a[(a.split==split)&(a.h==h)&(a.model==model)].iloc[0];err=d.pred-d.actual
 metric_error=max(metric_error,abs(r.MAE-abs(err).mean()),abs(r.RMSE-np.sqrt(np.mean(err**2))))
check('Independent forecast accuracy arithmetic',metric_error<1e-10,metric_error)
selected=pd.read_csv(T/'selected_models.csv')
for r in selected.itertuples():
 dev=a[(a.split=='development')&(a.h==r.h)&a.complete].sort_values(['MAE','RMSE','model'])
 check('Selection restricted to development, horizon '+str(r.h),r.model==dev.iloc[0].model,r.model)
check('Selected models have all 24 holdout targets',bool(a[(a.split=='holdout')&a.selected].n.eq(24).all()),24)
ct=pd.read_csv(T/'control_test_results.csv');check('Injected-fault controls passed',ct.passed.all(),len(ct))
runids=set()
for path in T.glob('*.csv'):
 d=pd.read_csv(path)
 if 'run_id' in d:runids.update(d.run_id.dropna().unique())
check('All R tables share one run ID',len(runids)==1,runids)
# Hash manifest excludes execution.log because it is open during the R run.
out=pd.read_csv(ROOT/'governance/output_manifest.csv')
check('Exported output SHA256',all(hashlib.sha256((ROOT/r.file).read_bytes()).hexdigest()==r.sha256 for r in out.itertuples()),len(out))
for image_path in (ROOT/'outputs/figures').glob('*.png'):
 with Image.open(image_path) as img:img.load()
check('All 12 PNG charts decode completely',len(list((ROOT/'outputs/figures').glob('*.png')))==12,12)
verification=pd.DataFrame(checks);verification['run_id']=next(iter(runids));verification.to_csv(ROOT/'governance/independent_verification.csv',index=False)
print(verification.to_string(index=False));print('INDEPENDENT VERIFICATION PASSED')
